"""Project RPC integration using disposable native profile databases."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer
from test_bridge import bridge


class ProjectWriteTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        directory = tempfile.TemporaryDirectory(prefix="companion-project-test-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        for home in (self.root, self.root / "profiles" / "second"):
            home.mkdir(parents=True, exist_ok=True)
            (home / "config.yaml").write_text("model: {}\n")
        env = patch.dict(os.environ, {"HERMES_HOME": str(self.root), "HERMES_KANBAN_HOME": str(self.root),
                                      "HERMES_KANBAN_DB": str(self.root / "kanban.db")})
        env.start(); self.addCleanup(env.stop)
        from tui_gateway import server
        scope = patch.object(server, "_hermes_home", str(self.root))
        scope.start(); self.addCleanup(scope.stop)
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

    async def create(self, profile="default"):
        response = await self.client.post("/api/companion/projects-create?profile=" + profile,
            json={"name": "Integration project", "folders": [str(self.root / "workspace")]})
        self.assertEqual(response.status, 200, await response.text())
        return (await response.json())["project"]

    async def testTwoWayNativeWritesStayInOwningProfile(self):
        project = await self.create("second")
        query = "?profile=second&project_id=" + project["id"]
        response = await self.client.patch("/api/companion/project-record" + query,
                                          json={"name": "Edited on phone", "description": "Two way validation"})
        self.assertEqual(response.status, 200, await response.text())
        from hermes_cli import projects_db
        with projects_db.connect_closing(self.root / "profiles" / "second" / "projects.db") as conn:
            stored = projects_db.get_project(conn, project["id"])
            self.assertEqual(stored.name, "Edited on phone")
            self.assertEqual(stored.description, "Two way validation")
            projects_db.update_project(conn, project["id"], name="Edited on Mac")
        response = await self.client.get("/api/companion/project-record" + query)
        self.assertEqual((await response.json())["project"]["name"], "Edited on Mac")
        response = await self.client.get("/api/companion/project-records?profile=default")
        self.assertEqual(response.status, 200, await response.text())
        self.assertEqual((await response.json())["projects"], [])
        response = await self.client.patch("/api/companion/project-record?profile=default&project_id=" + project["id"], json={"name": "Wrong owner"})
        self.assertEqual(response.status, 404, await response.text())
        self.assertIn("no such project", (await response.json())["error"]["message"])

    async def testFolderPrimaryArchiveAndActiveRoundTrip(self):
        project = await self.create()
        query = "?profile=default&project_id=" + project["id"]
        second_path = str(self.root / "second-folder")
        response = await self.client.post("/api/companion/project-folder" + query,
                                         json={"path": second_path, "label": "Reference", "is_primary": True})
        self.assertEqual(response.status, 200, await response.text())
        self.assertEqual((await response.json())["project"]["primary_path"], second_path)
        response = await self.client.post("/api/companion/project-primary" + query, json={"path": project["primary_path"]})
        self.assertEqual(response.status, 200, await response.text())
        self.assertEqual((await response.json())["project"]["primary_path"], project["primary_path"])
        response = await self.client.delete("/api/companion/project-folder" + query, json={"path": second_path})
        self.assertEqual(response.status, 200, await response.text())
        self.assertEqual(len((await response.json())["project"]["folders"]), 1)
        response = await self.client.post("/api/companion/project-active" + query, json={})
        self.assertEqual((await response.json())["active_id"], project["id"])
        for restore in (False, True):
            response = await self.client.post("/api/companion/project-archive" + query, json={"restore": restore})
            self.assertEqual(response.status, 200, await response.text())
            self.assertEqual((await response.json())["projects"][0]["archived"], not restore)
        response = await self.client.post("/api/companion/project-active?profile=default", json={})
        self.assertIsNone((await response.json())["active_id"])

    async def testDeleteRemovesOnlyTheProjectRecord(self):
        project = await self.create()
        folder = Path(project["primary_path"])
        folder.mkdir()
        file = folder / "keep.txt"
        file.write_text("Retain server files")
        query = "?profile=default&project_id=" + project["id"]
        await self.client.post("/api/companion/project-active" + query, json={})
        response = await self.client.delete("/api/companion/project-record" + query, json={})
        self.assertEqual(response.status, 400)
        self.assertIn("Clear the active project", (await response.json())["error"])
        await self.client.post("/api/companion/project-active?profile=default", json={})
        response = await self.client.delete("/api/companion/project-record" + query, json={})
        self.assertEqual(response.status, 200, await response.text())
        self.assertEqual((await response.json())["projects"], [])
        self.assertEqual(file.read_text(), "Retain server files")

    async def testInvalidFieldsAndDuplicatePrimaryRetainNativeReason(self):
        project = await self.create()
        response = await self.client.post("/api/companion/projects-create?profile=default",
            json={"name": "Duplicate", "folders": [project["primary_path"]]})
        self.assertEqual(response.status, 400, await response.text())
        self.assertIn("folder already belongs", (await response.json())["error"]["message"])
        query = "?profile=default&project_id=" + project["id"]
        for payload in ({"path": ""}, {"path": "relative"}, {"path": str(self.root), "is_primary": "false"}):
            response = await self.client.post("/api/companion/project-folder" + query, json=payload)
            self.assertEqual(response.status, 400)
        response = await self.client.post("/api/companion/project-primary" + query, json={"path": str(self.root / "foreign")})
        self.assertEqual(response.status, 400)
        response = await self.client.patch("/api/companion/project-record" + query, json={"name": "Changed", "profile": "second"})
        self.assertEqual(response.status, 400)
        response = await self.client.get("/api/companion/project-records?profile=missing")
        self.assertEqual(response.status, 400)

    async def testDeniedProjectWriteDoesNotInvokeRpc(self):
        self.allowed = False
        with patch.object(bridge, "rpc") as rpc:
            response = await self.client.post("/api/companion/projects-create?profile=default", json={"name": "Denied"})
        self.assertEqual(response.status, 401)
        rpc.assert_not_called()


if __name__ == "__main__":
    unittest.main()
