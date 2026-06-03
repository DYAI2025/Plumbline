# NEGATIVE FIXTURE — G1 challenge gate with NO token cap

This file deliberately describes the council challenge gate WITHOUT any
"N tokens" budget phrase, so that `gate_contracts.py token-bound` fails closed
(exit 1) and the G1-C7 contract check is proven non-vacuous.

The gate runs three roles (Challenger, Advisor, Critic) and produces a
one-page summary aimed at friction, not approval. No numeric token bound is
stated anywhere in this fixture.
