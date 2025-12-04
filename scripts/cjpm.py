# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///

import os
import sys
import subprocess
from pathlib import Path
import tomllib


def root_dir():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(script_dir)


def cpp_lds():
    return os.path.join(root_dir(), 'scripts', 'cpp.lds')



def read_version():
    cjpm_toml = os.path.join(root_dir(), "cjpm.toml")
    with open(cjpm_toml, "rb") as f:
        data = tomllib.load(f)
    return data["package"]["version"]


def preprocess_environment(env):
    ldflags = ""
    cangjie_home_dir = os.environ.get("CANGJIE_HOME")

    debug = "-g" in sys.argv

    match sys.platform:
        case "win32":
            ldflags += f" -L {cangjie_home_dir}/third_party/llvm/bin"

            if not debug:
                ldflags = "--strip-all" + ldflags
        case "darwin":
            ldflags += f"-search_paths_first -headerpad_max_install_names -L {cangjie_home_dir}/third_party/llvm/bin"
        case "linux":
            ldflags += f" --gc-sections --gc-keep-exported -L {cangjie_home_dir}/third_party/llvm/bin -T {cpp_lds()}"
            if not debug:
                ldflags = "--strip-all" + ldflags

    ldflags += " "

    if sys.platform != "darwin":
        ldflags += "--start-group "

    ldflags += " "

    match sys.platform:
        case "win32":
            ldflags += " -lclang -l:libstdc++.a -l:libwinpthread.a -lmingwex -lmsvcrt -lversion -lunwind "
        case "darwin":
            ldflags += " -lclang -lc++ -lc++abi -lSystem "
        case "linux":
            ldflags += " -lclang -l:libstdc++.a -lgcc_s "

    if sys.platform != "darwin":
        ldflags += "--end-group"

    env["LDFLAGS"] = ldflags
    print("ldflags:", ldflags, flush=True)
    env["CJBIND_VERSION"] = read_version()

    return env


def main():
    base_env = os.environ.copy()
    processed_env = preprocess_environment(base_env)

    command = ["cjpm"] + sys.argv[1:]

    process = subprocess.run(
        command,
        env=processed_env,
        stdin=sys.stdin,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )

    sys.exit(process.returncode)


if __name__ == "__main__":
    main()
