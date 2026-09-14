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
