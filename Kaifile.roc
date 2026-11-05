# Development environment and tasks for RocRay, realised by Kai.
#
#     kai run check        # pins, the scripts and the lints: what runs once, on one machine
#     kai run pins         # no compiler pin outside scripts/
#     kai run glue         # compare the committed host ABI with what `roc` generates
#     kai run glue-update  # regenerate the committed host ABI
#     kai run test         # build every host, then check, test, build and run every example
#     kai run docs         # render the manual (HTML, PDF, Markdown) into .docs-out/
#     kai shell            # the development environment
#     kai update           # refresh .kai/lock.json
#
# Two compilers are in play and are not interchangeable. `roc-stable` is the
# nightly named below; it runs the scripts under scripts/. Bare `roc` is the
# latest nightly, which the machine provides: the platform, its examples and
# its tests name no compiler.
app [kaifile] {
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.11/65bk6qdahqxn1mm6LR6Hkyw8dSdoeRZGwjNSuiPfvguP.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.11/std-6Jw5GxNCFkpnvBbnFmQg4KAVEn5bAfEveSZfDSzTDs42.tar.zst",
}

import std.Std

## A Roc nightly's compiler, for each system this project declares.
roc_nightly = |tag| {
	date = tag.drop_prefix("nightly-")
	file = |system, build| {
		top = "roc_nightly-${build}-${date}"
		{
			system,
			url: "https://github.com/roc-lang/nightlies/releases/download/${tag}/${top}.tar.gz",
			mirrors: [],
			program: Archive("${top}/roc"),
		}
	}
	[file("x86_64-linux", "linux_x86_64"), file("aarch64-darwin", "macos_apple_silicon")]
}

## A released file for each system this project declares, named by the system.
per_system = |prefix|
	["x86_64-linux", "aarch64-darwin"].map(|system| { system, url: "${prefix}${system.to_str()}", mirrors: [], program: File })

kaifile = Std.kaifile([
	Name("roc-ray"),
	Systems(["x86_64-linux", "aarch64-darwin"]),
	Packages("default", From(NixPackages("github:NixOS/nixpkgs/nixos-unstable"))),
	# .kai/lock.json records each download's digest, and the bytes are checked
	# before every use.
	FetchLocked("roc-stable", roc_nightly("nightly-2026-10-23-18478ff")),
	# The shared documentation renderer from roc-automation.
	FetchLocked("roc-docs", per_system("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.9.0/roc-docs-")),
	Environment("scripts", [Tools(["roc-stable#roc-stable"]), Expect(["roc", "git", "gh"])]),
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
	Task("check", [Use("dev"), Description("The pin check, the scripts' tests, checks and formatting, and `zig build lint`"), Run(["scripts/check_all.roc"])]),
	Task("pins", [Use("scripts"), Description("No compiler pin outside scripts/"), Run(["scripts/check_no_pins.roc"])]),
	Task("glue", [Use("dev"), Description("Compare the committed host ABI with what `roc` generates"), Run(["scripts/check_glue.roc"])]),
	Task("glue-update", [Use("dev"), Description("Regenerate the committed host ABI"), Run(["scripts/check_glue.roc", "--", "--update"])]),
	Task("test", [Use("dev"), Description("Build every host, then check, test, build and run every example"), Run(["zig", "build", "test"])]),
	# The manual, as the docs workflow builds it, for previewing locally.
	Task("docs", [Use("docs"), Description("Render the manual (HTML, PDF, Markdown) into .docs-out/"), Run(["roc-docs", "build", "--workspace", ".", "--pdf-filename", "roc-ray.pdf", "--site-url", "https://lukewilliamboswell.github.io/roc-ray/"])]),
	# The verified renderer's path, which CI hands to actions/build-docs.
	Task("docs-renderer", [Use("docs"), Run(["sh", "-c", "realpath \"$(command -v roc-docs)\""])]),
	# Release host libraries carry no Zig debug allocator; run after a ReleaseFast build.
	Task("check-release-hosts", [Use("scripts"), Run(["scripts/check_release_hosts.roc"])]),
	# The tooling compiler, as release notes record it.
	Task("compiler-version", [Use("scripts"), Run(["roc-stable", "version"])]),
])
