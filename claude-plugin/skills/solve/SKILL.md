---
name: solve
description: Route a goal through acc's scored-memory loop via acc_act(runtime="solve"); deliberate any returned brain_frame and submit via continue.
---

# solve

Routing sugar over the two MCP verbs — no logic lives here.

1. Call `acc_act(runtime="solve", input="<the goal>")`.
2. If the result is **final**: surface the answer, the `commitment` id, and the cited `[ids]`.
3. If the result is a **brain_frame**: it is YOUR deliberation turn — the frame is typed
   (which hole, what was retrieved, what is predicted). Reason over it, then submit via
   `acc_act(runtime="continue", input={"frame_id": ..., "submit_token": ..., "proposal_text": ...})`.
4. Never leave a received frame unresolved; never solo-derive outside the loop.
5. Close the commitment honestly later with `acc_act(runtime="outcome", ...)`.
