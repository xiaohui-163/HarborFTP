import ftplib, json, pathlib, select, subprocess, tempfile, time
base = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as root:
    p = subprocess.Popen([str(base/'.build/ftp-test'), root, '--controlled'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    def read():
        assert select.select([p.stdout], [], [], 3)[0]
        return p.stdout.readline().strip()
    def snapshot():
        p.stdin.write('connections\n'); p.stdin.flush()
        return json.loads(read())
    def expect(predicate):
        for _ in range(100):
            result = snapshot()
            if predicate(result): return result
            time.sleep(.02)
        raise AssertionError(result)
    try:
        assert read() == 'READY'
        first = ftplib.FTP(timeout=3); first.connect('127.0.0.1', 22121)
        rows = expect(lambda r: len(r)==1 and r[0]['activity']=='等待登录')
        assert rows[0]['ip']=='127.0.0.1' and 'username' not in rows[0]
        first.login('tester','test-password')
        rows = expect(lambda r: r[0].get('username')=='tester' and r[0]['activity']=='空闲')
        initial_id = rows[0]['id']
        second = ftplib.FTP(timeout=3); second.connect('127.0.0.1',22121); second.login()
        rows = expect(lambda r: len(r)==2 and any(x.get('username')=='anonymous' for x in r))
        assert len({x['id'] for x in rows})==2
        data = first.transfercmd('STOR active.bin'); data.sendall(b'x'*4096)
        expect(lambda r: any(x['activity']=='上传 · active.bin' and x['id']==initial_id for x in r))
        data.close(); first.voidresp()
        expect(lambda r: any(x['id']==initial_id and x['activity']=='空闲' for x in r))
        second.quit(); expect(lambda r: len(r)==1)
        p.stdin.write('stop\n'); p.stdin.flush(); assert read()=='STOPPED'
        assert snapshot()==[]
        first.close()
        print('PASS: IP, unauthenticated/authenticated/anonymous identity, distinct sessions, transfer activity, idle, disconnect, stop cleanup')
    finally:
        p.terminate(); p.wait(timeout=5)
