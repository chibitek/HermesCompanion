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


class ChangeFeedTests(unittest.IsolatedAsyncioTestCase):
    async def testAuthorizationPrecedesFilesystemReads(self):
        app = web.Application()
        adapter = Mock()
        adapter._check_auth.return_value = web.json_response({}, status=401)
        bridge.wire(app, adapter)
        async with TestClient(TestServer(app)) as client:
            with patch.object(bridge, "change_fingerprint") as reader:
                response = await client.get("/api/companion/changes")
                self.assertEqual(response.status, 401)
                reader.assert_not_called()

    async def testRealFileChangeProducesANewRevision(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.db-wal"
            path.write_bytes(b"first")
            app = web.Application()
            adapter = Mock()
            adapter._check_auth.return_value = None
            bridge.wire(app, adapter)
            with patch.object(bridge, "change_fingerprint", side_effect=lambda: bridge.fingerprint_paths([path])):
                async with TestClient(TestServer(app)) as client:
                    response = await client.get("/api/companion/changes")
                    self.assertEqual(response.headers["Content-Type"], "text/event-stream")
                    first = await response.content.readuntil(b"\n\n")
                    path.write_bytes(b"second revision")
                    import asyncio
                    second = await asyncio.wait_for(response.content.readuntil(b"\n\n"), timeout=3)
                    self.assertIn(b"workspace.changed", second)
                    self.assertNotEqual(first, second)
                    self.assertNotIn(str(path).encode(), second)
                    response.close()

    def testDeletionAndRecreationInvalidateRevision(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "projects.db"
            empty = bridge.fingerprint_paths([path])
            path.write_bytes(b"project")
            created = bridge.fingerprint_paths([path])
            self.assertNotEqual(empty, created)
            path.unlink()
            self.assertEqual(bridge.fingerprint_paths([path]), empty)


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


class ProjectDetailTests(unittest.TestCase):
    def setUp(self):
        patcher = patch.object(bridge, "project_session_limit", return_value=9001)
        patcher.start()
        self.addCleanup(patcher.stop)

    def testDiscoveredEmptyFolderUsesSameProfilesAuthoritativeOverview(self):
        project = {"id": "/repo", "sessionCount": 0, "repos": [{"groups": []}]}
        with patch.object(bridge, "rpc", side_effect=[
            {"profiles": [{"name": "assistant"}]}, {"project": None}, {"projects": [project]}
        ]) as rpc:
            detail = bridge.project_detail({"profile": "assistant", "project_id": "/repo"})
        self.assertEqual(detail["project"], project)
        self.assertEqual(rpc.call_args_list[-1].args, ("projects.tree", {"profile": "assistant", "session_limit": 9001}))
        self.assertEqual(rpc.call_args_list[1].args[1]["session_limit"], 9001)

    def testMissingOrNonemptyOverviewCannotMasqueradeAsHydratedHistory(self):
        for projects in [[], [{"id": "/other", "sessionCount": 0}],
                         [{"id": "/repo", "sessionCount": 1}], [{"id": "/repo"}]]:
            with self.subTest(projects=projects), patch.object(bridge, "rpc", side_effect=[
                {"profiles": [{"name": "assistant"}]}, {"project": None}, {"projects": projects}
            ]):
                detail = bridge.project_detail({"profile": "assistant", "project_id": "/repo"})
            self.assertIsNone(detail["project"])

    def testHydratedDetailNeverReplacedByOverview(self):
        detail = {"project": {"id": "/repo", "sessionCount": 2}}
        with patch.object(bridge, "rpc", side_effect=[
            {"profiles": [{"name": "assistant"}]}, detail
        ]) as rpc:
            self.assertEqual(bridge.project_detail({"profile": "assistant", "project_id": "/repo"}), detail)
        self.assertEqual(rpc.call_count, 2)


class ProjectSessionLimitTests(unittest.TestCase):
    def testCountUsesSelectedProfileReadOnlyAndIncludesAllRows(self):
        module = types.ModuleType("hermes_cli.web_routers.sessions")
        db = Mock()
        db.session_count.return_value = 12000
        module._with_db = Mock(side_effect=lambda profile, fn, **kwargs: fn(db))
        with patch.dict("sys.modules", {module.__name__: module}):
            self.assertEqual(bridge.project_session_limit("assistant"), 12001)
            db.session_count.return_value = 0
            self.assertEqual(bridge.project_session_limit("assistant"), 1)
        self.assertEqual(module._with_db.call_args.args[0], "assistant")
        self.assertEqual(module._with_db.call_args.kwargs, {"read_only": True})
        db.session_count.assert_called_with(include_archived=True)

    def testOverviewUsesEachProfilesCountRatherThanDefaultCap(self):
        def rpc(method, params):
            if method == "profiles.list":
                return {"profiles": [{"name": "first"}, {"name": "second"}]}
            self.assertEqual(params["session_limit"], {"first": 8001, "second": 12001}[params["profile"]])
            return {"projects": []}
        with patch.object(bridge, "rpc", side_effect=rpc), patch.object(
            bridge, "project_session_limit", side_effect=lambda name: {"first": 8001, "second": 12001}[name]
        ):
            result = bridge.projects({})
        self.assertEqual(len(result["groups"]), 2)
        self.assertEqual(result["errors"], [])


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
