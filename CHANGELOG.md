# Changelog

## [0.3.0](https://github.com/joshrotenberg/agent_workshop/compare/v0.2.0...v0.3.0) (2026-04-07)


### Features

* add shared state store, PubSub event bus, and telemetry ([#18](https://github.com/joshrotenberg/agent_workshop/issues/18)) ([87831e8](https://github.com/joshrotenberg/agent_workshop/commit/87831e87cddd2a1128cd25a4e3a250281b713e01))
* agent timeout + diagnostic logging for CLI hangs ([#49](https://github.com/joshrotenberg/agent_workshop/issues/49)) ([4044467](https://github.com/joshrotenberg/agent_workshop/commit/40444673fd5c2dd417a7046d66906ae7dd76656e))
* aw CLI binary with daemon mode and Burrito packaging ([#88](https://github.com/joshrotenberg/agent_workshop/issues/88)) ([8f3f145](https://github.com/joshrotenberg/agent_workshop/commit/8f3f14590612a07626e65ad0de960b14bdbe82f0))
* board workers — agents that poll and execute work items ([#35](https://github.com/joshrotenberg/agent_workshop/issues/35)) ([acaef5d](https://github.com/joshrotenberg/agent_workshop/commit/acaef5db58d8a7efeca09d323ff2d7b5cd80ef8c))
* declarative workflows -- staged pipelines with result flow ([#86](https://github.com/joshrotenberg/agent_workshop/issues/86)) ([622c2d4](https://github.com/joshrotenberg/agent_workshop/commit/622c2d4df775b599d011a57a833939127216c0fc))
* event log with live watch and history ([#25](https://github.com/joshrotenberg/agent_workshop/issues/25)) ([09f0f84](https://github.com/joshrotenberg/agent_workshop/commit/09f0f84d54159a85fb241008237a38c3068ad4eb))
* GitHub integration skill and example config ([#85](https://github.com/joshrotenberg/agent_workshop/issues/85)) ([039a7f0](https://github.com/joshrotenberg/agent_workshop/commit/039a7f001cb56bfdb584ec70cba94cfc99a00eb1))
* pass-through backend config support ([#31](https://github.com/joshrotenberg/agent_workshop/issues/31)) ([#82](https://github.com/joshrotenberg/agent_workshop/issues/82)) ([bd5008c](https://github.com/joshrotenberg/agent_workshop/commit/bd5008c1f4e3e5d688339f545084d1d7f44d0304))
* periodic task scheduler and cost budgets ([#20](https://github.com/joshrotenberg/agent_workshop/issues/20)) ([8b52ff2](https://github.com/joshrotenberg/agent_workshop/commit/8b52ff2af40001f75010d2ffd8ebe7a57269e62a))
* process monitoring + supervised board watchers ([#55](https://github.com/joshrotenberg/agent_workshop/issues/55), [#58](https://github.com/joshrotenberg/agent_workshop/issues/58)) ([#68](https://github.com/joshrotenberg/agent_workshop/issues/68)) ([21ef20d](https://github.com/joshrotenberg/agent_workshop/commit/21ef20d212777ac482bd3579d9e6dcf2cbf7e62c))
* proper OTP Application module (closes [#54](https://github.com/joshrotenberg/agent_workshop/issues/54), [#56](https://github.com/joshrotenberg/agent_workshop/issues/56), [#57](https://github.com/joshrotenberg/agent_workshop/issues/57)) ([#67](https://github.com/joshrotenberg/agent_workshop/issues/67)) ([e3d83fe](https://github.com/joshrotenberg/agent_workshop/commit/e3d83fed7466c0c2adff4f4fe947691a654b8e61))
* skills directory, AGENTS.md, and auto-injection into system prompts ([#30](https://github.com/joshrotenberg/agent_workshop/issues/30)) ([abaf0bd](https://github.com/joshrotenberg/agent_workshop/commit/abaf0bd9bd67df4375940876c72c2469b27e4336)), closes [#22](https://github.com/joshrotenberg/agent_workshop/issues/22)
* work board with lifecycle, dependencies, and agent claiming ([#21](https://github.com/joshrotenberg/agent_workshop/issues/21)) ([6a88178](https://github.com/joshrotenberg/agent_workshop/commit/6a88178a27ce436e97c4922c479cdfb44e5b745f)), closes [#16](https://github.com/joshrotenberg/agent_workshop/issues/16)
* workshop_tools, profiles, and work board MCP tools ([#23](https://github.com/joshrotenberg/agent_workshop/issues/23)) ([1a31873](https://github.com/joshrotenberg/agent_workshop/commit/1a318730820e40e9a8648d390de4e6e8f41599bf))
* worktree support for board workers ([#47](https://github.com/joshrotenberg/agent_workshop/issues/47)) ([a56a51a](https://github.com/joshrotenberg/agent_workshop/commit/a56a51a70f747afc6329d63aa2cf5f8c0eca04e8)), closes [#41](https://github.com/joshrotenberg/agent_workshop/issues/41)


### Bug Fixes

* atomic board claims using ETS take-and-reinsert ([#59](https://github.com/joshrotenberg/agent_workshop/issues/59)) ([#69](https://github.com/joshrotenberg/agent_workshop/issues/69)) ([7c6526e](https://github.com/joshrotenberg/agent_workshop/commit/7c6526e4a16b8497d9e15bb80946dcd2349dd6c4))
* board worker claims_completed counter now increments ([#50](https://github.com/joshrotenberg/agent_workshop/issues/50)) ([d84261e](https://github.com/joshrotenberg/agent_workshop/commit/d84261e8d3443ca3d8a4ccb08d69c2071234fc9a))
* board worker crash on Task result messages ([#37](https://github.com/joshrotenberg/agent_workshop/issues/37)) ([80591cf](https://github.com/joshrotenberg/agent_workshop/commit/80591cf76b9a263b768cb027524b3909c129e9b3))
* clean CLI output -- suppress epmd noise, lazy daemon detection ([#90](https://github.com/joshrotenberg/agent_workshop/issues/90)) ([2ae10bd](https://github.com/joshrotenberg/agent_workshop/commit/2ae10bdbcb069d9382de48efd3b89e26f4386753))
* event log color (light_black invisible on dark terminals) ([#27](https://github.com/joshrotenberg/agent_workshop/issues/27)) ([d9d24fb](https://github.com/joshrotenberg/agent_workshop/commit/d9d24fbb34f9ad49f65f6d9ea7f52b4bddf2b34d))
* force-kill stuck agents on dismiss/reset (3s timeout then kill) ([#34](https://github.com/joshrotenberg/agent_workshop/issues/34)) ([97861a9](https://github.com/joshrotenberg/agent_workshop/commit/97861a928eed4247a7511a3da2a7aa10f6214aa2))
* handle Node.start failure gracefully in client mode ([#89](https://github.com/joshrotenberg/agent_workshop/issues/89)) ([0d81e6a](https://github.com/joshrotenberg/agent_workshop/commit/0d81e6a1c8b6e0d21e7b2107d52fc23dedb7bcbd))
* info/1 reads session_id from ETS instead of blocking on backend ([#29](https://github.com/joshrotenberg/agent_workshop/issues/29)) ([fad71d6](https://github.com/joshrotenberg/agent_workshop/commit/fad71d642d3e74bcce5e30dacfbed6860c38d527)), closes [#28](https://github.com/joshrotenberg/agent_workshop/issues/28)
* log level control, better error messages ([#38](https://github.com/joshrotenberg/agent_workshop/issues/38)) ([#83](https://github.com/joshrotenberg/agent_workshop/issues/83)) ([676626f](https://github.com/joshrotenberg/agent_workshop/commit/676626f2a6b2d9ba8732e6f95895fdf7d5a9e71d))
* replace Task.yield with polling in MCP await/await_all tools ([#33](https://github.com/joshrotenberg/agent_workshop/issues/33)) ([4d94659](https://github.com/joshrotenberg/agent_workshop/commit/4d9465978c218c5a375659232682769367fbb646)), closes [#32](https://github.com/joshrotenberg/agent_workshop/issues/32)
* reset agent session between board work items ([#52](https://github.com/joshrotenberg/agent_workshop/issues/52)) ([0d0ab94](https://github.com/joshrotenberg/agent_workshop/commit/0d0ab943ebe225e691d4eb504f54f995a6898096))
* scheduler test race condition in schedules/0 test ([#73](https://github.com/joshrotenberg/agent_workshop/issues/73)) ([633a902](https://github.com/joshrotenberg/agent_workshop/commit/633a90228c10122be90b566f035870e9fe2cc810))
* suppress Anubis MCP debug logs by default ([#46](https://github.com/joshrotenberg/agent_workshop/issues/46)) ([f1ceef1](https://github.com/joshrotenberg/agent_workshop/commit/f1ceef12bd7eab5ddabb1acd99ed25c23c801f31)), closes [#42](https://github.com/joshrotenberg/agent_workshop/issues/42)
* suppress codex backend compile warnings ([#24](https://github.com/joshrotenberg/agent_workshop/issues/24)) ([73cf434](https://github.com/joshrotenberg/agent_workshop/commit/73cf4341002659fbe147d5ae2222d2c44cd6ec54))
* wrap codex backend in Code.ensure_loaded? guard ([#26](https://github.com/joshrotenberg/agent_workshop/issues/26)) ([00e7083](https://github.com/joshrotenberg/agent_workshop/commit/00e70834a48e198c8a14d8af8965c4a9405e37d2))

## [0.2.0](https://github.com/joshrotenberg/agent_workshop/compare/v0.1.0...v0.2.0) (2026-04-02)


### Features

* add MCP server (15 tools via anubis_mcp) ([528fdd1](https://github.com/joshrotenberg/agent_workshop/commit/528fdd17784dccd33626672b0687489273ad93a5))
* add mcp: option to configure/1 for auto-start ([73bdd31](https://github.com/joshrotenberg/agent_workshop/commit/73bdd313e0fe584e22478fc24e24949ec3006155))
* initial agent_workshop project ([52e43fa](https://github.com/joshrotenberg/agent_workshop/commit/52e43fa6439cc6f589883ea073f379ce15cb1ca6))


### Bug Fixes

* catch MCP server start failure (e.g. port in use) instead of crashing IEx ([67cb5a7](https://github.com/joshrotenberg/agent_workshop/commit/67cb5a775b9b308bf25e930ce2393833423cf473))
