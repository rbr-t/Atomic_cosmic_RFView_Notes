# Shared Hook Layer

This folder contains the starter deterministic hook layer adapted for the Atomic repository as a local overlay.

## Purpose

Hooks complement the existing agentic stack:

- agents decide and reason
- instructions and skills guide behavior
- hooks enforce non-negotiable runtime guardrails

## Current Starter Hooks

1. `01-session-start.json`
   Injects a short system message with repo role, current branch, and clean or dirty state.

2. `02-pretool-git-safety.json`
   Blocks clearly destructive git commands and asks before higher-risk git operations such as push-on-main or branch deletion.

3. `03-posttool-customization-validate.json`
   Validates changed customization files after tool use so malformed frontmatter or broken hook JSON is caught early.

## How This Applies To Atomic

- This repo is a domain-rich local overlay, not the shared source-of-truth baseline.
- Hooks help protect RF-specific customizations while still following the shared operating model.
- Hooks are intentionally small, auditable, and deterministic. They should not replace agent reasoning.

## Design Rules

- keep hooks short and fast
- avoid secrets in hook scripts
- block only when the boundary is real
- prefer warnings or ask flows over hard-deny when user approval may be reasonable
