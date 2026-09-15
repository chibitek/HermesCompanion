"""Native Kanban integration in a disposable SQLite home; never opens live boards.
Run with PYTHONPATH pointing to the installed Hermes checkout and its Python.
"""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer
from test_bridge import bridge


class TaskWriteTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="companion-kanban-test-")
        self.addCleanup(self.directory.cleanup)
        root = self.directory.name
        env = patch.dict(os.environ, {"HERMES_KANBAN_HOME": root, "HERMES_HOME": root,
                                      "HERMES_KANBAN_DB": str(Path(root) / "kanban.db")})
        env.start()
        # Use native per-board database resolution inside this disposable home.
        # A fixed DB override redirects every board into the default database.
        os.environ.pop("HERMES_KANBAN_DB", None)
        self.addCleanup(env.stop)
        from hermes_cli import kanban_db
        self.db = kanban_db
        self.assertEqual(kanban_db.kanban_db_path(), Path(root) / "kanban.db")
        self.allowed = True
        owner = self
        class Adapter:
            def _check_auth(self, request):
                return None if owner.allowed else web.json_response({}, status=401)
        app = web.Application()
        bridge.wire(app, Adapter())
        self.client = TestClient(TestServer(app))
        await self.client.start_server()
        self.addAsyncCleanup(self.client.close)

    async def testBoardManagementRoundTripAndRetryDoesNotOverwrite(self):
        from plugins.kanban.dashboard import plugin_api as native
        response = await self.client.post("/api/companion/boards", json={"slug": "mobile", "name": "Mobile board"})
        self.assertEqual(response.status, 200, await response.text())
        self.assertFalse((await response.json())["already_exists"])
        native.rename_board("mobile", native.RenameBoardBody(name="Desktop edit"))
        response = await self.client.post("/api/companion/boards", json={"slug": "mobile", "name": "Old retry"})
        result = await response.json()
        self.assertTrue(result["already_exists"])
        self.assertEqual(result["board"]["name"], "Desktop edit")
        response = await self.client.patch("/api/companion/board?board=mobile", json={"description": "From phone"})
        self.assertEqual(response.status, 200, await response.text())
        current = next(b for b in native.list_boards(include_archived=False)["boards"] if b["slug"] == "mobile")
        self.assertEqual(current["name"], "Desktop edit")
        self.assertEqual(current["description"], "From phone")
        response = await self.client.post("/api/companion/board-active?board=mobile", json={})
        self.assertEqual((await response.json())["current"], "mobile")
        task = native.create_task(native.CreateTaskBody(title="Archive preservation", triage=True), board="mobile")["task"]
        response = await self.client.post("/api/companion/board-archive?board=mobile", json={})
        receipt = await response.json()
        self.assertEqual(receipt["action"], "archived")
        self.assertEqual(receipt["current"], "default")
        self.assertNotIn("mobile", [b["slug"] for b in native.list_boards(include_archived=False)["boards"]])
        archived = list((self.db.boards_root() / "_archived").glob("mobile-*/kanban.db"))
        self.assertEqual(len(archived), 1)
        import sqlite3
        with sqlite3.connect(archived[0]) as db:
            self.assertEqual(db.execute("SELECT title FROM tasks WHERE id = ?", (task["id"],)).fetchone()[0], "Archive preservation")

    async def testBoardValidationAndAuthorizationPrecedeWrites(self):
        response = await self.client.post("/api/companion/boards", json={"slug": "../escape"})
        self.assertEqual(response.status, 400)
        response = await self.client.post("/api/companion/board-archive?board=default", json={})
        self.assertEqual(response.status, 400)
        self.assertIn("default", (await response.json())["error"]["message"])
        response = await self.client.post("/api/companion/board-archive?board=default", json={"delete": True})
        self.assertEqual(response.status, 400)
        response = await self.client.patch("/api/companion/board?board=missing", json={"name": "Renamed"})
        self.assertEqual(response.status, 400)
        self.allowed = False
        response = await self.client.post("/api/companion/boards", json={"slug": "unauthorized"})
        self.assertEqual(response.status, 401)
        self.assertNotIn("unauthorized", [b["slug"] for b in self.db.list_boards()])

    async def create(self, key="one"):
        response = await self.client.post("/api/companion/tasks?board=default", json={
            "title": "Verify Companion writes", "body": "Local integration validation",
            "triage": True, "idempotency_key": key})
        self.assertEqual(response.status, 200, await response.text())
        return (await response.json())["task"]

    async def testNativeRoundTripAndIdempotentCreation(self):
        task = await self.create()
        retry = await self.create()
        self.assertEqual(task["id"], retry["id"])
        self.assertEqual(task["status"], "triage")
        path = "/api/companion/task?board=default&task_id=" + task["id"]
        response = await self.client.patch(path, json={"title": "Edited from Companion", "body": "Updated description", "priority": 3, "status": "todo"})
        self.assertEqual(response.status, 200, await response.text())
        response = await self.client.post("/api/companion/task-comment?board=default&task_id=" + task["id"], json={"body": "Reviewed from phone"})
        self.assertEqual(response.status, 200, await response.text())
        from plugins.kanban.dashboard import plugin_api
        detail = plugin_api.get_task(task["id"], board="default", run_state_type=None, run_state_name=None)
        self.assertEqual(detail["task"]["title"], "Edited from Companion")
        self.assertEqual(detail["task"]["body"], "Updated description")
        self.assertEqual(detail["task"]["priority"], 3)
        self.assertEqual(detail["task"]["status"], "todo")
        self.assertEqual(detail["comments"][0]["body"], "Reviewed from phone")
        self.assertEqual(detail["comments"][0]["author"], "companion")
        # Read a change written by the native Mac handler through the phone endpoint.
        plugin_api.update_task(task["id"], plugin_api.UpdateTaskBody(title="Edited from Mac"), board="default")
        response = await self.client.get(path)
        self.assertEqual((await response.json())["task"]["title"], "Edited from Mac")

    async def testRefusalsIncludeNativeReasonAndDoNotHideState(self):
        task = await self.create()
        path = "/api/companion/task?board=default&task_id=" + task["id"]
        response = await self.client.patch(path, json={"status": "running"})
        self.assertEqual(response.status, 400)
        self.assertIn("running", (await response.json())["error"]["message"])
        response = await self.client.patch(path, json={"result": "Cannot be saved without completion"})
        self.assertEqual(response.status, 400)
        self.assertIn("requires a transition", (await response.json())["error"])
        response = await self.client.patch(path, json={"bogus": True})
        self.assertEqual(response.status, 400)
        self.assertIn("bogus", (await response.json())["error"])
        response = await self.client.patch(path, json={"priority": "high"})
        self.assertEqual(response.status, 422)
        self.assertIn("priority", (await response.json())["error"]["message"])
        response = await self.client.get(path)
        self.assertEqual((await response.json())["task"]["status"], "triage")

    async def testAuthorizationPrecedesMutationAndBodyParsing(self):
        self.allowed = False
        with patch.object(bridge, "require_board") as domain:
            response = await self.client.post("/api/companion/tasks?board=default", data="not json")
        self.assertEqual(response.status, 401)
        domain.assert_not_called()
        self.assertFalse(self.db.kanban_db_path().exists())

    async def testResumableAttachmentUploadReplayOwnershipAndDeletion(self):
        import base64, hashlib, uuid
        task = await self.create()
        other = await self.create("other")
        query = "?board=default&task_id=" + task["id"]
        data = "Phone attachment: café\n".encode()
        metadata = {"upload_id": str(uuid.uuid4()), "filename": "proof.txt", "content_type": "text/plain",
                    "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        async def post(route, body, status=200):
            response = await self.client.post("/api/companion/" + route + query, json=body)
            self.assertEqual(response.status, status, await response.text())
            return await response.json()
        self.assertEqual((await post("task-upload-begin", metadata))["offset"], 0)
        chunk = {"upload_id": metadata["upload_id"], "offset": 0, "data": base64.b64encode(data).decode()}
        self.assertEqual((await post("task-upload-chunk", chunk))["offset"], len(data))
        self.assertEqual((await post("task-upload-chunk", chunk))["offset"], len(data))
        self.assertEqual((await post("task-upload-begin", metadata))["offset"], len(data))
        await post("task-upload-begin", {**metadata, "filename": "changed.txt"}, 409)
        receipt = await post("task-upload-finish", {"upload_id": metadata["upload_id"]})
        attachment = receipt["attachment"]
        retry = await post("task-upload-finish", {"upload_id": metadata["upload_id"]})
        self.assertEqual(retry["attachment"]["id"], attachment["id"])
        # Recover the native receipt even if the final sidecar commit was lost.
        with bridge.upload_state({"board": "default", "task_id": task["id"]}, metadata) as directory:
            (directory / "state.json").unlink()
        await post("task-upload-begin", metadata)
        retry = await post("task-upload-finish", {"upload_id": metadata["upload_id"]})
        self.assertEqual(retry["attachment"]["id"], attachment["id"])
        response = await self.client.get("/api/companion/task-attachment" + query + "&attachment_id=" + str(attachment["id"]))
        self.assertEqual(await response.read(), data)
        response = await self.client.delete("/api/companion/task-attachment?board=default&task_id=" + other["id"], json={"attachment_id": attachment["id"]})
        self.assertEqual(response.status, 404)
        response = await self.client.delete("/api/companion/task-attachment" + query, json={"attachment_id": attachment["id"]})
        self.assertEqual(response.status, 200, await response.text())
        self.assertEqual((await response.json())["deleted"], True)
        await post("task-upload-finish", {"upload_id": metadata["upload_id"]}, 409)
        with bridge.upload_state({"board": "default", "task_id": task["id"]}, metadata) as directory:
            (directory / "state.json").unlink()
        await post("task-upload-begin", metadata, 409)

    async def testUploadAuthorizationLimitsAndDependencyRules(self):
        import hashlib, uuid
        task = await self.create()
        other = await self.create("dependency")
        query = "?board=default&task_id=" + task["id"]
        payload = {"parent_id": task["id"], "child_id": other["id"]}
        response = await self.client.post("/api/companion/task-link" + query, json=payload)
        self.assertEqual(response.status, 200, await response.text())
        response = await self.client.post("/api/companion/task-link" + query, json={"parent_id": other["id"], "child_id": task["id"]})
        self.assertEqual(response.status, 400)
        self.assertIn("cycle", await response.text())
        for _ in range(2):
            response = await self.client.delete("/api/companion/task-link" + query, json=payload)
            self.assertEqual(response.status, 200, await response.text())
            self.assertFalse((await response.json())["linked"])
        metadata = {"upload_id": str(uuid.uuid4()), "filename": "proof.txt", "content_type": "text/plain",
                    "size": 25 * 1024 * 1024 + 1, "sha256": hashlib.sha256(b"").hexdigest()}
        response = await self.client.post("/api/companion/task-upload-begin" + query, json=metadata)
        self.assertEqual(response.status, 413)
        self.allowed = False
        with patch.object(bridge, "attachment_context") as inspect_task:
            response = await self.client.post("/api/companion/task-upload-begin" + query, json={**metadata, "size": 0})
            self.assertEqual(response.status, 401)
            inspect_task.assert_not_called()

    async def testUnknownBoardAndMissingTaskAreRejected(self):
        response = await self.client.post("/api/companion/tasks?board=foreign", json={"title": "Unreachable", "idempotency_key": "two"})
        self.assertEqual(response.status, 400)
        task = await self.create()
        response = await self.client.patch("/api/companion/task?board=default&task_id=missing", json={"title": "Wrong task"})
        self.assertEqual(response.status, 404)
        response = await self.client.post("/api/companion/task-comment?board=default&task_id=" + task["id"], json={"body": "text", "author": "someone-else"})
        self.assertEqual(response.status, 400)


if __name__ == "__main__":
    unittest.main()
