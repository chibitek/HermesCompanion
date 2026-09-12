"""Run with Hermes's Python: python -m unittest discover -s GatewayPlugin."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import AsyncMock, patch
import types

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

if __name__ == "__main__":
    unittest.main()
