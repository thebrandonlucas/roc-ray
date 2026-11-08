# Development environment and tasks for RocRay, realised by Kai.
#
#     kai run check        # pins, the scripts and the lints: what runs once, on one machine
#     kai run pins         # no compiler pin outside scripts/
#     kai run glue         # compare the committed host ABI with what `roc` generates
#     kai run glue-update  # regenerate the committed host ABI
#     kai run test         # build every host, then check, test, build and run every example
#     kai run docs         # render the manual (HTML, PDF, Markdown) into .docs-out/
#     kai workflow ci      # check, then glue, as CI's checks job runs them
#     kai shell            # the development environment
#     kai update           # refresh .kai/lock.json
#
# Two compilers are in play and are not interchangeable. `roc-stable` is the
# nightly named below; it runs the scripts under scripts/. Bare `roc` is the
# latest nightly, which the machine provides: the platform, its examples and
# its tests name no compiler. The scripts and docs environments are pinned
# downloads, which need no Nix; dev adds Zig and its tools from nixpkgs.
app [kaifile] {
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.12/G3CQ6Ed3h7vyvV4eDvwH1J8UqBv2wEtkb9jLJhFkU5ny.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.12/std-6VuNBrdv6tT7ZAVD4bWGBYYwk1KJoXP7gCnFip5VSK11.tar.zst",
}

import std.Std

systems = ["x86_64-linux", "aarch64-darwin"]

# A Roc nightly's compiler, for each declared system.
roc_nightly = |tag| {
	nightly = |system, build| {
		top = "roc_nightly-${build}-${tag.drop_prefix("nightly-")}"
		{ system, url: "https://github.com/roc-lang/nightlies/releases/download/${tag}/${top}.tar.gz", mirrors: [], program: Archive("${top}/roc") }
	}
	[nightly("x86_64-linux", "linux_x86_64"), nightly("aarch64-darwin", "macos_apple_silicon")]
}

# A program released as one file per system, named by the system.
file = |url| systems.map(|system| { system, url: "${url}-${system.to_str()}", mirrors: [], program: File })

kaifile = Std.kaifile([
	Name("roc-ray"),
	Systems(systems),
	Packages("default", From(NixPackages("github:NixOS/nixpkgs/nixos-unstable"))),
	FetchLocked("roc-stable", roc_nightly("nightly-2026-10-23-18478ff")),
	# The shared documentation renderer from roc-automation. .kai/lock.json
	# records each system's digest, and the bytes are checked before every use.
	FetchLocked("roc-docs", file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.9.0/roc-docs")),
	Environment(
		"scripts",
		[
			Tools(["roc-stable#roc-stable"]),
			# Every bundle the scripts depend on, including dependencies of
			# dependencies: `roc-stable deps scripts/check_glue.roc` lists them.
			RocPackages(["https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst"]),
			Expect(["roc", "git", "gh"]),
		],
	),
	Environment(
		"dev",
		[
			Extend("scripts"),
			# The exact Zig release that builds the host and its linker inputs;
			# build.zig.zon names the same version.
			Tools(["zig_0_17", "python3", "zstd", "curl", "binutils"]),
		],
	),
	Environment("docs", [Tools(["roc-docs#roc-docs"]), Expect(["sh", "realpath"])]),
	Shell("default", [Use("dev")]),
	# The pin check, the scripts' tests, checks and formatting, and `zig build lint`.
	Task("check", [Use("dev"), Run(["scripts/check_all.roc"])]),
	Task("pins", [Use("scripts"), Run(["scripts/check_no_pins.roc"])]),
	Task("glue", [Use("dev"), Run(["scripts/check_glue.roc"])]),
	Task("glue-update", [Use("dev"), Run(["scripts/check_glue.roc", "--", "--update"])]),
	Task("test", [Use("dev"), Run(["zig", "build", "test"])]),
	# The manual, as the docs workflow builds it, for previewing locally.
	Task("docs", [Use("docs"), Run(["roc-docs", "build", "--workspace", ".", "--pdf-filename", "roc-ray.pdf", "--site-url", "https://lukewilliamboswell.github.io/roc-ray/"])]),
	# The verified renderer's path, which CI hands to actions/build-docs.
	Task("docs-renderer", [Use("docs"), Run(["sh", "-c", "realpath \"$(command -v roc-docs)\""])]),
	# Release host libraries carry no Zig debug allocator; run after a ReleaseFast build.
	Task("check-release-hosts", [Use("scripts"), Run(["scripts/check_release_hosts.roc"])]),
	# The tooling compiler, as release notes record it.
	Task("compiler-version", [Use("scripts"), Run(["roc-stable", "version"])]),
	Workflow("ci", [RunTask("check", []), RunTask("glue", [])]),
])
