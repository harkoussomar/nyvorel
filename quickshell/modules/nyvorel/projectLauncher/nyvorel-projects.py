#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


HOME = Path.home().resolve()
BASE_ROOT = (HOME / "dev-mine/projects").resolve()

EXCLUDED = {
    ".git",
    "node_modules",
    ".next",
    ".next-build",
    ".turbo",
    "dist",
    "build",
    "coverage",
    ".cache",
    ".gradle",
    ".idea",
    ".vscode",
    "target",
    "vendor",
    "__pycache__",
    ".venv",
    "venv",
    ".pnpm-store",
    "out",
    "tmp",
    ".output",
    ".dart_tool",
}

IMPORTANT_HIDDEN = {
    ".env",
    ".env.local",
    ".env.example",
    ".npmrc",
    ".gitignore",
    ".github",
}

PROJECT_MARKERS = {
    ".git",
    "package.json",
    "pnpm-workspace.yaml",
    "turbo.json",
    "nx.json",
    "pyproject.toml",
    "requirements.txt",
    "Pipfile",
    "Cargo.toml",
    "go.mod",
    "composer.json",
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "CMakeLists.txt",
    "Dockerfile",
    "docker-compose.yml",
    "docker-compose.yaml",
}


def run(cmd, timeout=2.5):
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def display_path(path):
    try:
        return "~/" + str(path.relative_to(HOME))
    except ValueError:
        return str(path)


def category_roots():
    if not BASE_ROOT.is_dir():
        return []

    try:
        roots = [
            item.resolve()
            for item in BASE_ROOT.iterdir()
            if item.is_dir()
            and not item.name.startswith(".")
        ]
    except OSError:
        return []

    return sorted(
        roots,
        key=lambda item: item.name.casefold(),
    )


def meaningful_children(path):
    try:
        return [
            item
            for item in path.iterdir()
            if item.name not in EXCLUDED
            and item.name not in {".DS_Store", "Thumbs.db"}
        ]
    except OSError:
        return []


def is_project(path):
    if not path.is_dir():
        return False

    entries = meaningful_children(path)

    # Empty directory = not a project.
    if not entries:
        return False

    # Strong project markers.
    for marker in PROJECT_MARKERS:
        if (path / marker).exists():
            return True

    # A non-empty directory can still be a useful project even when
    # it does not use a conventional build system.
    return True


def allowed_project(raw):
    candidate = Path(raw).expanduser().resolve()

    for category in category_roots():
        if (
            candidate.parent == category
            and candidate.is_dir()
            and is_project(candidate)
        ):
            return candidate

    raise ValueError(
        "project path is outside configured project categories"
    )


def read_json(path):
    try:
        data = json.loads(
            path.read_text(
                encoding="utf-8",
                errors="ignore",
            )
        )

        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def read_text(path, limit=200000):
    try:
        return path.read_text(
            encoding="utf-8",
            errors="ignore",
        )[:limit]
    except OSError:
        return ""


def markers(path):
    candidates = [
        "package.json",
        "pnpm-lock.yaml",
        "pnpm-workspace.yaml",
        "bun.lock",
        "bun.lockb",
        "yarn.lock",
        "package-lock.json",
        "pyproject.toml",
        "requirements.txt",
        "Pipfile",
        "Cargo.toml",
        "go.mod",
        "pom.xml",
        "build.gradle",
        "build.gradle.kts",
        "README.md",
        "README",
        "prisma/schema.prisma",
        "Dockerfile",
        "docker-compose.yml",
        "docker-compose.yaml",
        "turbo.json",
    ]

    return [
        item
        for item in candidates
        if (path / item).exists()
    ]


def list_projects():
    projects = []
    categories = []

    for category_root in category_roots():
        try:
            children = sorted(
                (
                    item
                    for item in category_root.iterdir()
                    if item.is_dir()
                    and not item.name.startswith(".")
                    and is_project(item)
                ),
                key=lambda item: item.name.casefold(),
            )
        except OSError:
            continue

        # Empty categories disappear completely.
        if not children:
            continue

        categories.append(category_root.name)

        for project in children:
            projects.append(
                {
                    "name": project.name,
                    "path": str(project),
                    "displayPath": display_path(project),
                    "group": category_root.name,
                    "markers": markers(project),
                    "git": (project / ".git").exists(),
                }
            )

    return {
        "projects": projects,
        "categories": categories,
        "tools": {
            name: shutil.which(name) is not None
            for name in ("code", "kitty", "zed")
        },
    }


def clean_md(line):
    line = re.sub(
        r"!\[[^\]]*\]\([^)]*\)",
        "",
        line,
    )

    line = re.sub(
        r"\[([^\]]+)\]\([^)]*\)",
        r"\1",
        line,
    )

    line = re.sub(
        r"<[^>]+>",
        "",
        line,
    )

    line = re.sub(
        r"^[#>*+\-\s]+",
        "",
        line,
    )

    line = re.sub(
        r"`([^`]+)`",
        r"\1",
        line,
    )

    line = re.sub(
        r"[*_~]",
        "",
        line,
    )

    return re.sub(
        r"\s+",
        " ",
        line,
    ).strip()


def readme_description(path):
    for name in (
        "README.md",
        "README",
        "readme.md",
        "Readme.md",
    ):
        file = path / name

        if not file.is_file():
            continue

        try:
            lines = file.read_text(
                encoding="utf-8",
                errors="ignore",
            ).splitlines()[:140]
        except OSError:
            continue

        fence = False
        paragraph = []

        for raw in lines:
            text = raw.strip()

            if text.startswith(
                ("```", "~~~")
            ):
                fence = not fence
                continue

            if fence:
                continue

            if not text:
                if paragraph:
                    result = clean_md(
                        " ".join(paragraph)
                    )

                    if len(result) >= 24:
                        return result[:260]

                    paragraph = []

                continue

            if text.startswith(
                (
                    "#",
                    "![",
                    "[![",
                    "<img",
                    "<picture",
                    "---",
                    "===",
                    "|",
                )
            ):
                continue

            if re.match(
                r"^\[[^\]]+\]:",
                text,
            ):
                continue

            paragraph.append(text)

        if paragraph:
            result = clean_md(
                " ".join(paragraph)
            )

            if len(result) >= 24:
                return result[:260]

    return ""


def description(path):
    package = read_json(
        path / "package.json"
    )

    value = package.get(
        "description"
    )

    if (
        isinstance(value, str)
        and value.strip()
    ):
        return value.strip()[:260]

    pyproject = path / "pyproject.toml"

    if pyproject.is_file():
        try:
            import tomllib

            data = tomllib.loads(
                pyproject.read_text(
                    encoding="utf-8"
                )
            )

            value = (
                data.get("project", {})
                .get("description", "")
            )

            if (
                isinstance(value, str)
                and value.strip()
            ):
                return value.strip()[:260]

        except Exception:
            pass

    return (
        readme_description(path)
        or "No project description found."
    )


def git_info(path):
    code, inside = run(
        [
            "git",
            "-C",
            str(path),
            "rev-parse",
            "--is-inside-work-tree",
        ]
    )

    if code or inside != "true":
        return {
            "isRepo": False,
            "branch": "",
            "clean": True,
            "changed": 0,
            "ahead": 0,
            "behind": 0,
        }

    _, branch = run(
        [
            "git",
            "-C",
            str(path),
            "branch",
            "--show-current",
        ]
    )

    if not branch:
        _, sha = run(
            [
                "git",
                "-C",
                str(path),
                "rev-parse",
                "--short",
                "HEAD",
            ]
        )

        branch = (
            "@" + sha
            if sha
            else "detached"
        )

    _, output = run(
        [
            "git",
            "-C",
            str(path),
            "status",
            "--porcelain=v1",
            "--untracked-files=normal",
            "--no-renames",
        ],
        3.0,
    )

    changed = (
        len(output.splitlines())
        if output
        else 0
    )

    ahead = 0
    behind = 0

    upstream, _ = run(
        [
            "git",
            "-C",
            str(path),
            "rev-parse",
            "--verify",
            "@{upstream}",
        ]
    )

    if upstream == 0:
        _, counts = run(
            [
                "git",
                "-C",
                str(path),
                "rev-list",
                "--left-right",
                "--count",
                "@{upstream}...HEAD",
            ]
        )

        numbers = re.findall(
            r"\d+",
            counts,
        )

        if len(numbers) >= 2:
            behind = int(numbers[0])
            ahead = int(numbers[1])

    return {
        "isRepo": True,
        "branch": branch,
        "clean": changed == 0,
        "changed": changed,
        "ahead": ahead,
        "behind": behind,
    }


def stack_scan_directories(path, max_depth=3):
    base_depth = len(path.parts)

    for current, dirs, files in os.walk(path):
        current_path = Path(current)

        depth = (
            len(current_path.parts)
            - base_depth
        )

        dirs[:] = [
            name
            for name in dirs
            if name not in EXCLUDED
            and not name.startswith(".")
        ]

        if depth > max_depth:
            dirs[:] = []
            continue

        yield (
            current_path,
            set(files),
        )


def scope_name(base, current):
    try:
        parts = current.relative_to(
            base
        ).parts
    except ValueError:
        return ""

    if not parts:
        return ""

    return "/".join(parts[:2])


def stack_info(path):
    detected = {}

    def add(
        name,
        icon,
        current,
        priority,
    ):
        scope = scope_name(
            path,
            current,
        )

        item = detected.get(name)

        if item is None:
            item = {
                "name": name,
                "icon": icon,
                "priority": priority,
                "root": False,
                "scopes": set(),
            }

            detected[name] = item

        item["priority"] = min(
            item["priority"],
            priority,
        )

        if not scope:
            item["root"] = True
            item["scopes"].clear()
        elif not item["root"]:
            item["scopes"].add(
                scope
            )

    for folder, names in stack_scan_directories(
        path,
        max_depth=3,
    ):
        package = {}

        if "package.json" in names:
            package = read_json(
                folder / "package.json"
            )

            dependencies = {}

            for key in (
                "dependencies",
                "devDependencies",
                "peerDependencies",
            ):
                section = package.get(
                    key
                )

                if isinstance(
                    section,
                    dict,
                ):
                    dependencies.update(
                        section
                    )

            # Major frameworks.
            if "next" in dependencies:
                add(
                    "Next.js",
                    "▲",
                    folder,
                    10,
                )
            elif "nuxt" in dependencies:
                add(
                    "Nuxt",
                    "󱄆",
                    folder,
                    10,
                )
            elif "@sveltejs/kit" in dependencies:
                add(
                    "SvelteKit",
                    "",
                    folder,
                    10,
                )
            elif "@angular/core" in dependencies:
                add(
                    "Angular",
                    "",
                    folder,
                    10,
                )
            elif "astro" in dependencies:
                add(
                    "Astro",
                    "󰬐",
                    folder,
                    10,
                )
            elif "react" in dependencies:
                add(
                    "React",
                    "󰜈",
                    folder,
                    12,
                )
            elif "vue" in dependencies:
                add(
                    "Vue",
                    "󰡄",
                    folder,
                    12,
                )
            elif "svelte" in dependencies:
                add(
                    "Svelte",
                    "",
                    folder,
                    12,
                )

            # Backend frameworks.
            if "@nestjs/core" in dependencies:
                add(
                    "NestJS",
                    "",
                    folder,
                    11,
                )

            if "fastify" in dependencies:
                add(
                    "Fastify",
                    "󰛴",
                    folder,
                    13,
                )

            if "express" in dependencies:
                add(
                    "Express",
                    "",
                    folder,
                    14,
                )

            # Build/runtime.
            if (
                "vite" in dependencies
                and not any(
                    name in detected
                    for name in (
                        "Next.js",
                        "Nuxt",
                        "SvelteKit",
                        "Angular",
                        "Astro",
                    )
                )
            ):
                add(
                    "Vite",
                    "󰐣",
                    folder,
                    25,
                )

            if (
                "typescript" in dependencies
                or "tsconfig.json" in names
            ):
                add(
                    "TypeScript",
                    "󰛦",
                    folder,
                    20,
                )

            if (
                "tailwindcss" in dependencies
                or "@tailwindcss/postcss"
                    in dependencies
            ):
                add(
                    "Tailwind",
                    "󱏿",
                    folder,
                    30,
                )

            if (
                "@prisma/client"
                    in dependencies
                or "prisma"
                    in dependencies
                or (
                    folder
                    / "prisma/schema.prisma"
                ).exists()
            ):
                add(
                    "Prisma",
                    "",
                    folder,
                    24,
                )

        if "pnpm-lock.yaml" in names:
            add(
                "pnpm",
                "󰏗",
                folder,
                40,
            )
        elif (
            "bun.lock" in names
            or "bun.lockb" in names
        ):
            add(
                "Bun",
                "",
                folder,
                40,
            )
        elif "yarn.lock" in names:
            add(
                "Yarn",
                "󰏗",
                folder,
                40,
            )
        elif "package-lock.json" in names:
            add(
                "npm",
                "",
                folder,
                40,
            )

        if (
            "turbo.json" in names
            or ".turbo" in names
        ):
            add(
                "Turborepo",
                "󱂬",
                folder,
                34,
            )

        if "nx.json" in names:
            add(
                "Nx",
                "󰘦",
                folder,
                34,
            )

        if (
            "Dockerfile" in names
            or "docker-compose.yml" in names
            or "docker-compose.yaml" in names
        ):
            add(
                "Docker",
                "󰡨",
                folder,
                35,
            )

        if (
            "pyproject.toml" in names
            or "requirements.txt" in names
            or "Pipfile" in names
        ):
            add(
                "Python",
                "",
                folder,
                20,
            )

            combined = (
                read_text(
                    folder
                    / "pyproject.toml"
                )
                + "\n"
                + read_text(
                    folder
                    / "requirements.txt"
                )
            ).lower()

            if "fastapi" in combined:
                add(
                    "FastAPI",
                    "󱂛",
                    folder,
                    12,
                )

            if "django" in combined:
                add(
                    "Django",
                    "",
                    folder,
                    12,
                )

            if "flask" in combined:
                add(
                    "Flask",
                    "󰛊",
                    folder,
                    13,
                )

        if "Cargo.toml" in names:
            add(
                "Rust",
                "",
                folder,
                20,
            )

        if "go.mod" in names:
            add(
                "Go",
                "",
                folder,
                20,
            )

        if (
            "build.gradle" in names
            or "build.gradle.kts" in names
        ):
            add(
                "Gradle",
                "",
                folder,
                32,
            )

            if (
                folder
                / "app"
            ).is_dir():
                add(
                    "Android",
                    "",
                    folder,
                    15,
                )

        if "pom.xml" in names:
            add(
                "Java",
                "",
                folder,
                20,
            )

        if (
            folder
            / "prisma/schema.prisma"
        ).exists():
            add(
                "Prisma",
                "",
                folder,
                24,
            )

    result = []

    for item in sorted(
        detected.values(),
        key=lambda value: (
            value["priority"],
            value["name"].casefold(),
        ),
    ):
        scopes = sorted(
            item["scopes"]
        )

        result.append(
            {
                "name": item["name"],
                "icon": item["icon"],
                "scope": (
                    ""
                    if item["root"]
                    else ", ".join(
                        scopes[:2]
                    )
                ),
            }
        )

    if not result:
        result.append(
            {
                "name": "Project",
                "icon": "󰲋",
                "scope": "",
            }
        )

    return result[:9]


def compact_tree(path, limit=18):
    rows = []

    preferred = {
        "src": 0,
        "app": 1,
        "apps": 2,
        "frontend": 3,
        "backend": 4,
        "packages": 5,
        "prisma": 6,
        "docs": 7,
        ".github": 8,
    }

    def children(directory):
        try:
            values = [
                item
                for item in directory.iterdir()
                if item.name not in EXCLUDED
                and (
                    not item.name.startswith(".")
                    or item.name
                        in IMPORTANT_HIDDEN
                )
            ]
        except OSError:
            return []

        return sorted(
            values,
            key=lambda item: (
                preferred.get(
                    item.name.rstrip("/"),
                    100,
                ),
                not item.is_dir(),
                item.name.casefold(),
            ),
        )

    def walk(directory, depth):
        if (
            depth >= 3
            or len(rows) >= limit
        ):
            return

        values = children(directory)

        max_children = (
            11
            if depth == 0
            else 7
        )

        for item in values[:max_children]:
            if len(rows) >= limit:
                break

            is_directory = (
                item.is_dir()
            )

            rows.append(
                {
                    "depth": depth,
                    "name": (
                        item.name + "/"
                        if is_directory
                        else item.name
                    ),
                    "isDir": is_directory,
                }
            )

            if is_directory:
                walk(
                    item,
                    depth + 1,
                )

    walk(
        path,
        0,
    )

    return rows


def preview(raw):
    project = allowed_project(raw)

    return {
        "name": project.name,
        "path": str(project),
        "displayPath": display_path(project),
        "description": description(project),
        "git": git_info(project),
        "stack": stack_info(project),
        "tree": compact_tree(project),
        "markers": markers(project),
    }


def main():
    if len(sys.argv) < 2:
        print(
            json.dumps(
                {
                    "error":
                        "missing command"
                }
            )
        )
        return 2

    try:
        if sys.argv[1] == "list":
            print(
                json.dumps(
                    list_projects(),
                    ensure_ascii=False,
                )
            )
            return 0

        if (
            sys.argv[1] == "preview"
            and len(sys.argv) >= 3
        ):
            print(
                json.dumps(
                    preview(
                        sys.argv[2]
                    ),
                    ensure_ascii=False,
                )
            )
            return 0

    except Exception as error:
        print(
            json.dumps(
                {
                    "error":
                        str(error)
                },
                ensure_ascii=False,
            )
        )
        return 1

    print(
        json.dumps(
            {
                "error":
                    "unknown command"
            }
        )
    )

    return 2


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
