#!/usr/bin/env python3
"""Build only cidre's pomace static targets with Command Line Tools.

This project-local adapter is not Xcode and rejects other projects/actions.
"""
import subprocess
import sys
from pathlib import Path


def main():
    args = sys.argv[1:]
    values = {}
    targets = []
    output = None
    for index, arg in enumerate(args):
        if arg in ['-project', '-sdk', '-arch', '-configuration']:
            values[arg] = args[index + 1]
        elif arg == '-target':
            targets.append(args[index + 1])
        elif arg.startswith('SYMROOT='):
            output = Path(arg.split('=', 1)[1])
    project = Path(values.get('-project', ''))
    if (project.as_posix() != 'pomace/pomace.xcodeproj'
            or values.get('-sdk') != 'macosx'
            or values.get('-arch') != 'arm64'
            or 'build' not in args or output is None or not targets):
        raise SystemExit('This adapter supports only cidre pomace macOS arm64 static targets.')
    configuration = values.get('-configuration', 'Release')
    if configuration not in ['Release', 'Debug']:
        raise SystemExit('Unsupported configuration')
    destination = output / configuration
    destination.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    minimum = next((arg.split('=', 1)[1] for arg in args
                    if arg.startswith('MACOSX_DEPLOYMENT_TARGET=')), '12.3')
    for target in targets:
        if not target.replace('_', '').isalnum():
            raise SystemExit('Invalid pomace target')
        source = Path('pomace') / target / (target + '.m')
        if not source.is_file():
            raise SystemExit('Missing pomace source: ' + str(source))
        obj = destination / (target + '.o')
        command = ['xcrun', 'clang', '-arch', 'arm64', '-isysroot', sdk,
                   '-mmacosx-version-min=' + minimum, '-fobjc-arc', '-fmodules',
                   '-fmodules-cache-path=' + str(output / 'ModuleCache'),
                   '-O2' if configuration == 'Release' else '-O0',
                   '-c', str(source), '-o', str(obj)]
        subprocess.run(command, check=True)
        subprocess.run(['xcrun', 'libtool', '-static', '-o',
                        str(destination / ('lib' + target + '.a')), str(obj)], check=True)
        print('Built cidre pomace target using Command Line Tools:', target)


if __name__ == '__main__':
    main()
