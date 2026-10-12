#!/usr/bin/env python3
"""Generates an image with the Higgsfield API (Recraft V4.1) and saves it under art_src/.

    ~/.config/higgsfield/venv/bin/python tool/art/hf_gen.py <name> <aspect> "<prompt>"

Each call is a paid generation. The key is read from ~/.config/higgsfield/credentials.env
(never from the repository). Every prompt is recorded in art_src/prompts.json so an image can
be traced and remade.
"""
import json
import os
import sys
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
OUT = os.path.join(ROOT, 'art_src')
MODEL = 'recraft/v4.1/text-to-image'


def load_key():
    path = os.path.expanduser('~/.config/higgsfield/credentials.env')
    for line in open(path):
        if line.startswith('HF_KEY='):
            os.environ['HF_KEY'] = line.split('=', 1)[1].strip()
            return
    sys.exit('HF_KEY not found in ' + path)


def main():
    name, aspect, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
    target = os.path.join(OUT, name + '.png')
    if os.path.exists(target) and '--force' not in sys.argv:
        print('exists, skipped:', target)
        return
    load_key()
    import higgsfield_client
    try:
        result = higgsfield_client.subscribe(MODEL, arguments={
            'prompt': prompt, 'resolution': '1k', 'aspect_ratio': aspect, 'output_format': 'png'})
    except Exception as e:  # moderated, failed, out of credits: say so, never pretend
        sys.exit('generation failed: %s: %s' % (type(e).__name__, str(e)[:300]))
    images = (result or {}).get('images') or []
    if not images:
        sys.exit('no image in the result: ' + json.dumps(result)[:300])
    os.makedirs(OUT, exist_ok=True)
    urllib.request.urlretrieve(images[0]['url'], target)
    log_path = os.path.join(OUT, 'prompts.json')
    log = json.load(open(log_path)) if os.path.exists(log_path) else {}
    log[name] = {'model': MODEL, 'aspect': aspect, 'prompt': prompt}
    json.dump(log, open(log_path, 'w'), indent=1, ensure_ascii=False)
    print('saved', target)


if __name__ == '__main__':
    main()
