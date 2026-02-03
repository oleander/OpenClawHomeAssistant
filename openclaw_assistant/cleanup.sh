#!/usr/bin/env python3
import sys

def main():
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        
        # Parse supervisor event
        headers = dict(x.split(':') for x in line.split())
        payload = sys.stdin.read(int(headers['len']))
        
        # Check if it's openclaw exiting
        if 'openclaw' in payload and ('EXITED' in line or 'FATAL' in line):
            print('[INFO] OpenClaw stopped; cleaning up session locks', flush=True)
            import subprocess
            subprocess.run([
                'bash', '-c',
                'rm -f /config/.openclaw/agents/main/sessions/*.jsonl.lock || true'
            ])
        
        # Acknowledge the event
        sys.stdout.write('RESULT 2\nOK')
        sys.stdout.flush()

if __name__ == '__main__':
    main()
