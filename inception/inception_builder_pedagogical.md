# Inception Pedagogical Builder

*Purpose, scope, and learning goals for `inception_builder_pedagogical.sh`*

## Table of Contents

- [What This Script Is](#what-this-script-is)
- [Primary Goals](#primary-goals)
- [Who Should Use It](#who-should-use-it)
- [High-Level Workflow](#high-level-workflow)
- [Configuration Model](#configuration-model)
- [Fast Mode and Tag Resolution](#fast-mode-and-tag-resolution)
- [Generated Project Structure](#generated-project-structure)
- [Learning-First Design Decisions](#learning-first-design-decisions)
- [Recommended Learning Path](#recommended-learning-path)

## What This Script Is

`inception_builder_pedagogical.sh` is a configuration-driven scaffold generator for the 42 Inception project.
It produces a runnable Docker/Compose baseline while keeping each generated file readable and heavily documented.

> [!note] Why this builder exists
> The script prioritizes understanding over automation magic.
> You get a working baseline quickly, then learn by modifying concrete files.

## Primary Goals

- Lower setup friction for first-time Docker learners.
- Generate a complete but minimal stack from `inception.conf`.
- Keep all generated configs and entrypoints pedagogical and editable.
- Support both predefined services and custom service names.
- Encourage iterative hardening after first successful run.

## Who Should Use It

Use this builder if you want to:
- Learn container architecture step by step.
- See exactly where each runtime value comes from.
- Start with a working project and then customize safely.

Avoid this builder if your only goal is production-grade deployment with no educational context.

## High-Level Workflow

1. Read existing `inception.conf`, or generate a template if missing.
2. Validate required fields in watchdog mode.
3. Load configuration values into generation variables.
4. Resolve image tags (or use pinned fallback tags).
5. Generate output tree (`Makefile`, `.env`, `docker-compose.yml`, service folders).
6. Print a concise summary with next steps.

## Configuration Model

The script accepts:
- Built-in services: `nginx`, `mariadb`, `wordpress`, `redis`, `ftp`, `adminer`, `static`.
- Custom services: any safe lowercase service name (`[a-z0-9_-]`).

Built-in services receive tailored Dockerfiles and configs.
Custom services receive a generic scaffold you can adapt.

Key flags in `inception.conf`:
- `overwrite`: controls replacement behavior when output folder already exists.
- `fast_mode`: prioritizes speed for generation/build workflow.
- `resolve_tags`: controls Docker Hub live tag lookup independently from `fast_mode`.

## Fast Mode and Tag Resolution

`fast_mode` and `resolve_tags` are related but separate:

- `fast_mode: true` focuses on faster local iteration.
- `resolve_tags: false` skips network lookups and uses pinned fallback tags.
- `resolve_tags: true` forces Docker Hub lookup even if fast mode is enabled.

> [!tip] Practical profile for unstable networks
> Use:
> `fast_mode: true`
> `resolve_tags: false`
>
> This avoids remote tag discovery and usually gives more reliable local loops.

## Generated Project Structure

The generated folder includes:
- `Makefile`: build/run helper targets.
- `srcs/.env`: environment variables consumed by services.
- `srcs/docker-compose.yml`: service orchestration and volumes.
- `srcs/requirements/<service>/`: Dockerfile, configs, entrypoint/tools.

## Learning-First Design Decisions

The builder intentionally favors clarity:
- Comments explain why each important setting exists.
- Service scripts include safe fallback behavior where possible.
- Defaults are runnable, not production-hardened.

> [!warning] Educational baseline, not production baseline
> Generated files are designed for learning.
> Before real deployment, review security, secrets handling, networking, and healthchecks.

## Recommended Learning Path

1. Generate with only one or two services.
2. Read each generated Dockerfile and entrypoint end to end.
3. Add one service at a time and observe compose/network changes.
4. Enable stricter settings (passwords, service dependencies, healthchecks).
5. Refactor toward your target architecture once concepts are clear.
