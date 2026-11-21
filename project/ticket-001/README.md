# Ticket 001: Install Bielik and live Polish speech on Jetson Orin

- **ID**: ticket-001
- **Owner**: agent:codex
- **Status**: IN_PROGRESS
- **Workflow state**: EDIT
- **Created**: 2026-11-21

## Goal and scope

SESSION_EXECUTION_AUTHORIZATION from the project owner in this session. Implement, test, and publish the requested installation site for Jetson Orin. Planfile PLF-001, GitHub issue #1.

## Acceptance criteria

- [ ] AC-01: Install the public distribution with one command on JetPack Ubuntu.
- [ ] AC-02: Serve local Bielik chat and Polish streaming speech with usable client examples.
- [ ] AC-03: Publish the verified installer and site through the protected project workflow.

## Verification

The candidate served real Bielik 1.5B Q8_0 on x86-64 through SubLLM in buffered and SSE modes. A real WebSocket client received 159 partial results and 12 finals for 108.36 seconds of Polish FLEURS audio. The 2-thread CPU run scored 35/215 word errors, compared to 33/215 for faster-whisper small INT8. Deployment on physical Jetson hardware is still pending. Mobile/desktop browser checks and clipboard interaction passed.

## Publication dependencies

OneDev PLF-29705 and Validator VA-097 track protected publication admission. First adoption also requires separating the target-owned bootstrap files from the installer workstream.

## Tracking boundary

This directory contains the minimal reviewed intent. Optional participant prose
and raw command logs are not required delivery output.

<!-- ticket-radar:start -->
## Ticket Radar

Initial planned-scope estimate; advisory only, not execution or merge approval.

| Measure | Initial assessment |
| --- | --- |
| Impact score | 72/100 |
| Complexity | L |
| Estimated effort | 224 min |
| Planning budget | 30 min |
| Split recommended | yes |

Diagnostics: RADAR-ACCEPTANCE-MISSING, RADAR-BUDGET-EXCEEDED.
<!-- ticket-radar:end -->
