import ftplib, io, os, pathlib, subprocess, tempfile
base = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as root:
    pathlib.Path(root, 'escape').symlink_to('/private/tmp')
    process = subprocess.Popen([str(base / '.build/ftp-test'), root], stdout=subprocess.PIPE, text=True)
    try:
        assert process.stdout.readline().strip() == 'READY'
        ftp = ftplib.FTP(); ftp.connect('127.0.0.1', 22121); ftp.login('tester', 'test-password')
        content = os.urandom(200000)
        ftp.storbinary('STOR 测试.bin', io.BytesIO(content))
        downloaded = io.BytesIO(); ftp.retrbinary('RETR 测试.bin', downloaded.write)
        assert downloaded.getvalue() == content
        assert ftp.size('测试.bin') == len(content)
        assert '测试.bin' in ftp.nlst()
        ftp.mkd('folder'); ftp.rename('测试.bin', 'folder/renamed.bin'); ftp.cwd('folder')
        assert ftp.pwd() == '/folder'
        ftp.delete('renamed.bin'); ftp.cwd('/'); ftp.rmd('folder')
        for path in ['/../', '/escape']:
            try: ftp.cwd(path)
            except ftplib.error_perm: pass
            else: raise AssertionError('escaped root: ' + path)
        ftp.quit()
        anon = ftplib.FTP(); anon.connect('127.0.0.1', 22121); anon.login()
        try: anon.storbinary('STOR denied', io.BytesIO(b'no'))
        except ftplib.error_perm: pass
        else: raise AssertionError('anonymous wrote file')
        anon.quit()
        bad = ftplib.FTP(); bad.connect('127.0.0.1', 22121)
        try: bad.login('tester', 'wrong')
        except ftplib.error_perm: pass
        else: raise AssertionError('bad password accepted')
        bad.close()
        print('PASS: binary upload/download, UTF-8, listing, size, rename, directories, delete, traversal/symlink protection, anonymous read-only, authentication')
    finally:
        process.terminate(); process.wait(timeout=5)
