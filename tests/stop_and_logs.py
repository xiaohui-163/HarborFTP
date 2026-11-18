import ftplib, io, pathlib, select, socket, struct, subprocess, tempfile, time
base = pathlib.Path(__file__).resolve().parents[1]

def login():
    f = ftplib.FTP(timeout=3)
    f.connect('127.0.0.1', 22121)
    f.login('tester', 'test-password')
    return f

def refused(port):
    try:
        s = socket.create_connection(('127.0.0.1', port), timeout=.5)
    except OSError:
        return
    s.close()
    raise AssertionError(f'port {port} still accepts connections')

with tempfile.TemporaryDirectory() as folder:
    root = pathlib.Path(folder)
    with open(root / 'events.log', 'w+') as logs:
        p = subprocess.Popen([str(base / '.build/ftp-test'), folder, '--controlled'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=logs, text=True)
        def response(expected):
            assert select.select([p.stdout], [], [], 4)[0], 'server did not finish stopping'
            assert p.stdout.readline().strip() == expected
        def command(cmd):
            p.stdin.write(cmd+'\n'); p.stdin.flush()
            response('STOPPED' if cmd == 'stop' else 'STARTED')
        def events():
            logs.flush(); logs.seek(0); return logs.read()
        try:
            response('READY')
            f = login()
            f.storbinary('STOR success.bin', io.BytesIO(b'abc' * 10000))
            result = io.BytesIO(); f.retrbinary('RETR success.bin', result.write)
            assert result.getvalue() == b'abc' * 10000
            try: f.retrbinary('RETR missing.bin', lambda _: None)
            except ftplib.error_perm: pass
            else: raise AssertionError('missing file succeeded')
            f.quit()
            # Both an idle control connection and an unused passive listener must close.
            idle = login(); host, passive = idle.makepasv()
            command('stop'); refused(22121); refused(passive)
            try: idle.voidcmd('NOOP')
            except (OSError, EOFError, ftplib.Error): pass
            else: raise AssertionError('old control session still works')
            idle.close(); command('start')
            # Stop while awaiting a passive data connection.
            waiting = login(); host, passive = waiting.makepasv()
            waiting.putcmd('RETR success.bin'); assert waiting.getresp().startswith('150')
            command('stop'); refused(passive); waiting.close(); command('start')
            # Mid-upload: keep the original file, discard temporary partial data.
            (root / 'interrupted.bin').write_bytes(b'original')
            upload = login(); data = upload.transfercmd('STOR interrupted.bin')
            data.sendall(b'x' * 65536)
            command('stop'); data.close(); upload.close()
            assert (root / 'interrupted.bin').read_bytes() == b'original'
            assert not list(root.glob('.harbor-*'))
            refused(22121); command('start')
            # Mid-download: a large sparse file prevents completion before stop.
            with open(root / 'large.bin', 'wb') as out: out.truncate(128 * 1024 * 1024)
            download = login(); data = download.transfercmd('RETR large.bin')
            assert data.recv(1024)
            command('stop')
            total = 1024
            data.settimeout(2)
            try:
                while True:
                    chunk = data.recv(65536)
                    if not chunk: break
                    total += len(chunk)
            except ConnectionResetError: pass
            assert total < 128 * 1024 * 1024
            data.close(); download.close(); command('start')
            # Peer reset is a failed upload, never a completed upload.
            reset = login(); data = reset.transfercmd('STOR reset.bin'); data.sendall(b'x' * 4096)
            data.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0)); data.close()
            try: reset.voidresp()
            except ftplib.error_perm: pass
            else: raise AssertionError('reset was accepted')
            reset.close()
            # Multiple rapid restarts must not reuse an old accept loop.
            for _ in range(10):
                f = login(); command('stop'); f.close(); refused(22121); command('start')
            command('stop')
            text = events()
            for token in ['上传开始 · success.bin', '上传完成 · success.bin · 30000 字节', '下载完成 · success.bin · 30000 字节', '下载失败 · missing.bin', '上传中断 · interrupted.bin', '下载中断 · large.bin', '上传失败 · reset.bin']:
                assert token in text, (token, text)
            for name in ['interrupted.bin', 'reset.bin']:
                assert '上传完成 · '+name not in text
            assert '下载完成 · large.bin' not in text
            print('PASS: new/old connections, passive ports, waiting data, active upload/download, atomic upload, reset failure logs, byte counts, 10 restarts')
        finally:
            p.terminate(); p.wait(timeout=5)
