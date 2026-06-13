---
name: frames
description: Drain acc's deliberation queue — open/waiting brain_frames checkpointed by headless runs — via acc_act(runtime="continue").
---

# frames

Routing sugar over the two MCP verbs — no logic lives here.

1. List the queue: `acc frames` (CLI, read-only observation).
2. For each open/waiting frame: read its typed hole + retrieved context, deliberate,
   then submit via
   `acc_act(runtime="continue", input={"frame_id": ..., "submit_token": ..., "proposal_text": ...})`.
3. An identical duplicate submit replays the cached result — resubmitting is safe.
4. Surface each resolution's `commitment` id and cited `[ids]`; drain the queue fully
   before taking new work — checkpointed frames are work headless runs saved for you.
