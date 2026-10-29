#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the native app against fragmented and malformed printer streams."""
import io
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading
import time

from PIL import Image
from pypdf import PdfReader

APP = Path(__file__).parent / 'dist/Scan Connector for Mac.app/Contents/MacOS/Scan Connector for Mac'


def read_to_end(sock):
    result = bytearray()
    while not result.endswith(b'\x80'):
        block = sock.recv(1)
        if not block:
            raise RuntimeError('App closed request early')
        result += block
    return bytes(result)


def fixture(malformed=False):
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 54921))
    server.listen(1)
    errors = []
    def serve():
        try:
            with server, server.accept()[0] as connection:
                connection.settimeout(10)
                connection.sendall(b'+OK 200\r\n')
                assert read_to_end(connection) == b'\x1bQ\n\x80'
                connection.sendall(b'\xc1' + b'\0' * 74)
                assert read_to_end(connection) == b'\x1bQDI\n\x80'
                connection.sendall(b'\0QDI' + struct.pack('<I', 4) + b'test')
                request = read_to_end(connection)
                assert request.startswith(b'\x1bSSP\nOS=MAC\nPSRC=FB\n')
                connection.sendall(b'\0SSP' + struct.pack('<I', 0))
                assert read_to_end(connection).startswith(b'\x1bXSC\n')
                if malformed:
                    connection.sendall(b'\x01\x02\x01\x00\x15\x00')
                    return
                for page in range(2):
                    image = Image.new('RGB', (32, 16), 'red' if page == 0 else 'blue')
                    buffer = io.BytesIO(); image.save(buffer, 'JPEG'); data = buffer.getvalue()
                    half = len(data) // 2
                    for part in [data[:half], data[half:]]:
                        frame = struct.pack('<BBHHII', 0, 2, 1, 21, len(part), 16) + part
                        # Fragment both headers and JPEG payload across socket reads.
                        for offset in range(0, len(frame), 7):
                            connection.sendall(frame[offset:offset+7])
                    connection.sendall(struct.pack('<BBHH', 0, 1 if page == 0 else 33, 1, 0x2000))
        except BaseException as error:
            errors.append(error)
    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    return thread, errors


for mode in ['color', 'grayscale', 'text']:
    with tempfile.TemporaryDirectory() as directory:
        thread, errors = fixture()
        result = subprocess.run([str(APP), '--scan-test', '--host', '127.0.0.1', '--output', directory, '--mode', mode], capture_output=True, text=True, timeout=30)
        thread.join(3)
        assert not errors, errors
        assert result.returncode == 0, (result.stdout, result.stderr)
        pdfs = list(Path(directory).glob('*.pdf'))
        assert len(pdfs) == 1
        document = PdfReader(pdfs[0])
        assert len(document.pages) == 2
        assert all(len(page.images) == 1 for page in document.pages)
        for page in document.pages:
            image_objects = [item.get_object() for item in page['/Resources']['/XObject'].values() if item.get_object().get('/Subtype') == '/Image']
            assert len(image_objects) == 1
            assert image_objects[0]['/BitsPerComponent'] == (1 if mode == 'text' else 8)
            if mode != 'color':
                space = image_objects[0]['/ColorSpace']
                assert space == '/DeviceGray' or (isinstance(space,list) and space[0] == '/ICCBased' and space[1].get_object()['/N'] == 1), repr(space)
        assert not list(Path(directory).glob('.*.partial.pdf'))
        print(f'PASS: fragmented two-page stream becomes valid {mode} PDF with correct bit depth')

with tempfile.TemporaryDirectory() as directory:
    thread, errors = fixture(malformed=True)
    result = subprocess.run([str(APP), '--scan-test', '--host', '127.0.0.1', '--output', directory], capture_output=True, text=True, timeout=30)
    thread.join(3)
    assert not errors, errors
    assert result.returncode != 0
    assert not list(Path(directory).iterdir())
    print('PASS: scanner error rejects the scan and removes partial output')
