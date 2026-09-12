"""Run with Hermes's Python: python -m unittest discover -s GatewayPlugin."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import AsyncMock, Mock, patch
import types
import tempfile

from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

spec = importlib.util.spec_from_file_location("companion_bridge", Path(__file__).parent / "hermes-companion" / "__init__.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeRoutesTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.allowed = False
        self.reads = 0
        owner = self

        class Adapter:
            def _check_auth(self, request):
                return None if owner.allowed else web.json_response({}, status=401)

        def reader(query):
            self.reads += 1
            if query.get("async"):
                async def snapshot():
                    return {"async": True}
                return snapshot()
            return {"received": query.get("value")}

        app = web.Application()
        with patch.dict(bridge.READERS, {"projects": reader}, clear=True):
            bridge.wire(app, Adapter())
        self.client = TestClient(TestServer(app))
        await self.client.start_server()

    async def asyncTearDown(self):
        await self.client.close()

    async def testDeniedRequestsNeverReadWorkspace(self):
        response = await self.client.get("/api/companion/projects")
        self.assertEqual(response.status, 401)
        self.assertEqual(self.reads, 0)


    async def testUsesExistingAuthorizationAndDisablesCaching(self):
        self.allowed = True
        response = await self.client.get("/api/companion/projects?value=folder")
        self.assertEqual(await response.json(), {"received": "folder"})
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertEqual(self.reads, 1)

    async def testNoProfileAliasesOrWriteRoutes(self):
        self.allowed = True
        response = await self.client.get("/p/other/api/companion/projects")
        self.assertEqual(response.status, 404)
        response = await self.client.post("/api/companion/projects")
        self.assertEqual(response.status, 405)
        self.assertEqual(self.reads, 0)

    async def testAwaitsAsynchronousDomainReaders(self):
        self.allowed = True
        response = await self.client.get("/api/companion/projects?async=true")
        self.assertEqual(response.status, 200)
        self.assertEqual(await response.json(), {"async": True})


class BotHistoryTests(unittest.IsolatedAsyncioTestCase):
    async def testCanonicalPointerAndOwnerComeFromRoster(self):
        reader = AsyncMock(return_value={"profile": "assistant", "messages": []})
        module = types.ModuleType("hermes_cli.web_routers.sessions")
        module.get_session_messages = reader
        roster = {"profiles": [{"name": "assistant", "canonical_session": {"id": "canonical"}}]}
        with patch.object(bridge, "rpc", return_value=roster), patch.dict(
            "sys.modules", {"hermes_cli.web_routers.sessions": module}
        ):
            await bridge.bot_history({"profile": "assistant", "offset": "100", "session_id": "foreign"})
        reader.assert_awaited_once_with("canonical", profile="assistant", limit=100,
                                        offset=100, order="latest", include_compacted=False)

    async def testUnknownProfileDoesNotFallBackToDefault(self):
        module = types.ModuleType("hermes_cli.web_routers.sessions")
        module.get_session_messages = AsyncMock()
        with patch.object(bridge, "rpc", return_value={"profiles": []}), patch.dict(
            "sys.modules", {"hermes_cli.web_routers.sessions": module}
        ):
            with self.assertRaises(ValueError):
                await bridge.bot_history({"profile": "missing"})
        module.get_session_messages.assert_not_awaited()

    async def testNoCanonicalChatDoesNotShowUnrelatedLatestSession(self):
        module = types.ModuleType("hermes_cli.web_routers.sessions")
        module.get_session_messages = AsyncMock()
        roster = {"profiles": [{"name": "assistant", "last_session": {"id": "unrelated"}}]}
        with patch.object(bridge, "rpc", return_value=roster), patch.dict(
            "sys.modules", {"hermes_cli.web_routers.sessions": module}
        ):
            history = await bridge.bot_history({"profile": "assistant"})
        self.assertIsNone(history["session_id"])
        self.assertEqual(history["messages"], [])
        module.get_session_messages.assert_not_awaited()

class TaskDetailTests(unittest.TestCase):
    def testScopesTaskReadAndExplicitlyClearsHTTPQueryDefaults(self):
        module = types.ModuleType("plugins.kanban.dashboard.plugin_api")
        module.list_boards = Mock(return_value={"boards": [{"slug": "engineering"}]})
        module.get_task = Mock(return_value={"task": {"id": "task", "latest_summary": "full"}, "comments": [], "runs": []})
        with patch.dict("sys.modules", {module.__name__: module}):
            detail = bridge.task_detail({"board": "engineering", "task_id": "task"})
        self.assertEqual(detail["board"], "engineering")
        self.assertEqual(detail["task"]["latest_summary"], "full")
        module.get_task.assert_called_once_with("task", board="engineering", run_state_type=None, run_state_name=None)

    def testUnknownBoardNeverReadsTask(self):
        module = types.ModuleType("plugins.kanban.dashboard.plugin_api")
        module.list_boards = Mock(return_value={"boards": []})
        module.get_task = Mock()
        with patch.dict("sys.modules", {module.__name__: module}):
            with self.assertRaises(ValueError):
                bridge.task_detail({"board": "../foreign", "task_id": "task"})
        module.get_task.assert_not_called()


class ProjectHistoryTests(unittest.IsolatedAsyncioTestCase):
    async def testChecksProjectMembershipBeforeReadingHistory(self):
        module = types.ModuleType("hermes_cli.web_routers.sessions")
        module.get_session_messages = AsyncMock(return_value={"profile": "assistant", "session_id": "resumed"})
        detail = {"project": {"repos": [{"groups": [{"sessions": [{"id": "selected"}]}]}]}}
        query = {"profile": "assistant", "project_id": "project", "session_id": "selected", "offset": "100"}
        with patch.object(bridge, "project_detail", return_value=detail), patch.dict("sys.modules", {module.__name__: module}):
            result = await bridge.project_history(query)
            with self.assertRaises(ValueError):
                await bridge.project_history(dict(query, session_id="foreign"))
            with self.assertRaises(ValueError):
                await bridge.project_history(dict(query, offset="-1"))
        self.assertEqual(result["requested_session_id"], "selected")
        self.assertEqual(result["project_id"], "project")
        self.assertEqual(result["history"]["session_id"], "resumed")
        module.get_session_messages.assert_awaited_once_with("selected", profile="assistant", limit=100,
                                                            offset=100, order="latest", include_compacted=False)


class TaskAttachmentTests(unittest.IsolatedAsyncioTestCase):
    async def testDownloadRequiresAuthAndTaskMembership(self):
        from starlette.responses import FileResponse

        module = types.ModuleType("plugins.kanban.dashboard.plugin_api")
        allowed = False

        class Adapter:
            def _check_auth(self, request):
                return None if allowed else web.json_response({}, status=401)

        detail = {"attachments": [{"id": 7, "task_id": "selected"}]}
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "report.txt"
            file.write_text("Attachment bytes")
            module.download_attachment = Mock(return_value=FileResponse(file, filename="report.txt", media_type="text/plain"))
            app = web.Application()
            with patch.dict(bridge.READERS, {"task-attachment": bridge.task_attachment}, clear=True):
                bridge.wire(app, Adapter())
            with patch.object(bridge, "task_detail", return_value=detail), patch.dict("sys.modules", {module.__name__: module}):
                async with TestClient(TestServer(app)) as client:
                    path = "/api/companion/task-attachment?board=engineering&task_id=selected&attachment_id=7"
                    response = await client.get(path)
                    self.assertEqual(response.status, 401)
                    module.download_attachment.assert_not_called()
                    allowed = True
                    response = await client.get(path.replace("attachment_id=7", "attachment_id=8"))
                    self.assertEqual(response.status, 400)
                    module.download_attachment.assert_not_called()
                    response = await client.get(path)
                    self.assertEqual(response.status, 200)
                    self.assertEqual(await response.text(), "Attachment bytes")
                    self.assertEqual(response.headers["Cache-Control"], "no-store")
                    self.assertEqual(response.headers["X-Content-Type-Options"], "nosniff")
                    self.assertIn("report.txt", response.headers["Content-Disposition"])
            module.download_attachment.assert_called_once_with(7, board="engineering")


if __name__ == "__main__":
    unittest.main()
