#!/usr/bin/env python3
"""Checks that every FiveM native called by the resource really exists.

Uses the official declaration sources:
  * GTA natives  : https://github.com/citizenfx/natives            (client side)
  * CFX natives  : https://github.com/citizenfx/fivem ext/native-decls (with apiset)

Usage:
  git clone --depth 1 https://github.com/citizenfx/natives /tmp/natives
  git clone --depth 1 --filter=blob:none --sparse https://github.com/citizenfx/fivem /tmp/fivem
  (cd /tmp/fivem && git sparse-checkout set ext/native-decls)
  python3 tests/check_natives.py /tmp/natives /tmp/fivem/ext/native-decls
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Functions provided by the CfxLua runtime itself (citizen/scripting/lua/scheduler.lua),
# not by native declarations.
RUNTIME = {
    'CreateThread', 'Wait', 'SetTimeout', 'ClearTimeout', 'RegisterNetEvent', 'RegisterServerEvent',
    'AddEventHandler', 'RemoveEventHandler', 'TriggerEvent', 'TriggerServerEvent', 'TriggerClientEvent',
    'RegisterNUICallback', 'SendNUIMessage', 'GetPlayers', 'GetPlayerIdentifiers', 'PerformHttpRequest',
}


ARITY = {}


def lua_name(native):
    name = native.lower().replace('0x', '')
    name = re.sub(r'_([a-z])', lambda m: m.group(1).upper(), name)
    return name[:1].upper() + name[1:]


def read_decls(folder, cfx):
    names = {}
    for dirpath, _, files in os.walk(folder):
        for file in files:
            if not file.endswith('.md'):
                continue
            with open(os.path.join(dirpath, file), encoding='utf-8', errors='ignore') as fh:
                text = fh.read()
            match = re.search(r'^##\s+([A-Z0-9_]+)\s*$', text, re.M)
            if not match:
                continue
            apiset = 'client'
            if cfx:
                api = re.search(r'^apiset:\s*(\w+)', text, re.M)
                apiset = api.group(1) if api else 'shared'
            names.setdefault(lua_name(match.group(1)), set()).add(apiset)
            sig = re.search(r'```c\s*(?://[^\n]*\n\s*)*[\w*\s]+?\b' + match.group(1) + r'\s*\((.*?)\);', text, re.S)
            if sig:
                params = [p.strip() for p in sig.group(1).split(',') if p.strip() and p.strip() != 'void']
                # pointer params are either outputs (returned in Lua) or handles passed by
                # reference (Blip*, Entity*...), so accept any count between the two readings
                pointers = [p for p in params if re.match(r'^(?!char)\w+\s*\*', p)]
                for n in range(len(params) - len(pointers), len(params) + 1):
                    ARITY.setdefault(lua_name(match.group(1)), set()).add(n)
            aliases = re.search(r'^aliases:\s*\[(.*?)\]', text, re.M)
            if aliases:
                for alias in re.findall(r'"_?([A-Z0-9_]+)"', aliases.group(1)):
                    names.setdefault(lua_name(alias), set()).add(apiset)
    return names


def defined_in_project():
    defined = set()
    for dirpath, _, files in os.walk(ROOT):
        if '/tests' in dirpath or '/html' in dirpath:
            continue
        for file in files:
            if file.endswith('.lua'):
                with open(os.path.join(dirpath, file), encoding='utf-8') as fh:
                    text = fh.read()
                defined.update(re.findall(r'function\s+([A-Z]\w*)\s*\(', text))
                defined.update(re.findall(r'^([A-Z]\w*)\s*=', text, re.M))
                defined.update(re.findall(r'local\s+function\s+([A-Za-z]\w*)', text))
    return defined


def calls_in(path):
    with open(path, encoding='utf-8') as fh:
        text = fh.read()
    text = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
    text = re.sub(r'--[^\n]*', '', text)
    text = re.sub(r"'(?:[^'\\]|\\.)*'", "''", text)
    text = re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)
    found = set()
    for match in re.finditer(r'(?<![.:\w])([A-Z][A-Za-z0-9_]*)\s*\(', text):
        found.add(match.group(1))
    return found


def call_arities(path):
    with open(path, encoding='utf-8') as fh:
        text = fh.read()
    text = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
    text = re.sub(r'--[^\n]*', '', text)
    text = re.sub(r"'(?:[^'\\]|\\.)*'", "''", text)
    text = re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)
    result = []
    for match in re.finditer(r'(?<![.:\w])([A-Z][A-Za-z0-9_]*)\s*\(', text):
        depth, i, args, empty = 1, match.end(), 0, True
        while i < len(text) and depth:
            c = text[i]
            if c in '({[':
                depth += 1
            elif c in ')}]':
                depth -= 1
            elif c == ',' and depth == 1:
                args += 1
            if depth and not c.isspace() and not (c == ',' and depth == 1):
                empty = False
            i += 1
        body = text[match.end():i]
        if re.search(r'\bfunction\b', body):
            continue  # inline function bodies contain their own commas
        result.append((match.group(1), 0 if empty else args + 1))
    return result


def manifest_files():
    with open(os.path.join(ROOT, 'fxmanifest.lua'), encoding='utf-8') as fh:
        text = fh.read()
    def block(name):
        m = re.search(name + r'\s*\{(.*?)\}', text, re.S)
        return re.findall(r"'([^']+\.lua)'", m.group(1)) if m else []
    return block('shared_scripts'), block('server_scripts'), block('client_scripts')


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    gta = read_decls(sys.argv[1], cfx=False)
    cfx = read_decls(sys.argv[2], cfx=True)
    defined = defined_in_project()
    shared, server, client = manifest_files()

    def allowed(name, side):
        if name in RUNTIME or name in defined:
            return True
        if side == 'client' and name in gta:
            return True
        return bool(cfx.get(name, set()) & {'shared', side})

    problems = []
    checked = set()
    for side, files in (('server', shared + server), ('client', shared + client)):
        for file in files:
            for name in sorted(calls_in(os.path.join(ROOT, file))):
                checked.add(name)
                if file in shared:
                    # shared files guard side-specific calls with IsDuplicityVersion(); accept either side
                    if allowed(name, 'server') or allowed(name, 'client'):
                        continue
                elif allowed(name, side):
                    continue
                problems.append(f'{file}: {name}() is not a known {side} native')

    for side, files in (('server', shared + server), ('client', shared + client)):
        for file in files:
            for name, count in call_arities(os.path.join(ROOT, file)):
                if name in ARITY and name not in defined and name not in RUNTIME and count not in ARITY[name]:
                    problems.append(f'{file}: {name}() called with {count} argument(s), official signature takes {sorted(ARITY[name])}')

    natives_used = sorted(n for n in checked if n not in defined and n not in RUNTIME)
    print(f'GTA natives known: {len(gta)}, CFX natives known: {len(cfx)}')
    print(f'Natives used by the resource: {len(natives_used)}')
    print('  ' + ', '.join(natives_used))
    if problems:
        print('\nPROBLEMS:')
        for p in sorted(set(problems)):
            print('  ' + p)
        return 1
    print('\nAll native calls exist, are used on the correct side (client/server) and pass the right number of arguments.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
