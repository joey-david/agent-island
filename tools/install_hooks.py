"""Idempotently add Agent Island hooks to Claude Code and Codex (removes older island-hook entries)."""
import json, os, shutil

HOOK = os.path.expanduser('~/.agent-island/bin/island-hook')
WAIT = 12 * 3600  # a question can sit until you get to it

CLAUDE = [
    ('SessionStart', None, False), ('SessionEnd', None, False), ('UserPromptSubmit', None, False),
    ('PostToolUse', None, False), ('Notification', None, False), ('Stop', None, False),
    ('PreToolUse', 'AskUserQuestion', True), ('PermissionRequest', None, True),
]
CODEX = [
    ('SessionStart', None, False), ('SessionEnd', None, False), ('UserPromptSubmit', None, False),
    ('PostToolUse', None, False), ('Stop', None, False),
]  # no PermissionRequest: an empty reply makes Codex ask you instead of its auto-reviewer


def merge(path, agent, plan):
    data = {}
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)
        if not os.path.exists(path + '.bak-agent-island'):
            shutil.copy2(path, path + '.bak-agent-island')
    hooks = data.setdefault('hooks', {})
    for event in list(hooks):
        groups = []
        for g in hooks[event]:
            g['hooks'] = [h for h in g.get('hooks', []) if 'island-hook' not in h.get('command', '')]
            if g['hooks']:
                groups.append(g)
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]
    for event, matcher, wait in plan:
        h = {'type': 'command', 'command': f'{HOOK} --agent {agent}' + (' --wait' if wait else '')}
        if wait:
            h['timeout'] = WAIT
        g = {'hooks': [h]}
        if matcher:
            g['matcher'] = matcher
        hooks.setdefault(event, []).append(g)
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    os.replace(tmp, path)
    print('hooks:', path)


merge(os.path.expanduser('~/.claude/settings.json'), 'claude', CLAUDE)
if os.path.isdir(os.path.expanduser('~/.codex')):
    merge(os.path.expanduser('~/.codex/hooks.json'), 'codex', CODEX)
