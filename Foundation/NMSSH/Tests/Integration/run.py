"""Exercise the real NMSSH transport against local SSH fixtures.

Requires macOS, Xcode tools, and `pip install 'paramiko>=3,<5'` in the running Python env.
No real credentials or remote servers are used.
"""
import pathlib
import socket
import subprocess
import tempfile
import threading
import time

import paramiko

ROOT = pathlib.Path(__file__).resolve().parents[2]
HOST_KEY = paramiko.RSAKey.generate(2048)


class Fixture(paramiko.ServerInterface):
    def __init__(self, case):
        self.case = case
        self.channels = 0
        self.keepalives = 0
        self.shell_inputs = bytearray()
        self.transport = None
        self.stop = threading.Event()

    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL if (username, password) == ("fixture", "fixture") else paramiko.AUTH_FAILED

    def get_allowed_auths(self, username):
        return "password"

    def check_channel_request(self, kind, chanid):
        self.channels += 1
        if self.channels > 1:
            if self.case == "refused":
                return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
            if self.case == "unresponsive" or (self.case == "resume-unresponsive" and self.channels > 2):
                self.stop.wait(10)
            if self.case == "remote-disconnect":
                # Exercise libssh2's disconnect callback while the channel's
                # mutex is held. Cleanup must wait until libssh2 has returned.
                message = paramiko.Message()
                message.add_byte(bytes([paramiko.common.MSG_DISCONNECT]))
                message.add_int(11)
                message.add_string("fixture disconnect")
                message.add_string("")
                self.transport._send_message(message)
                time.sleep(0.05)
                self.transport.close()
                return paramiko.OPEN_FAILED_CONNECT_FAILED
            if self.case == "disconnected":
                self.transport.close()
                return paramiko.OPEN_FAILED_CONNECT_FAILED
        return paramiko.OPEN_SUCCEEDED

    def check_channel_pty_request(self, *args):
        return True

    def check_channel_shell_request(self, channel):
        def output():
            try:
                channel.settimeout(0.05)
                while not self.stop.is_set() and not channel.closed:
                    channel.send(b"fixture output\r\n")
                    try:
                        self.shell_inputs.extend(channel.recv(1024))
                    except socket.timeout:
                        pass
                    time.sleep(0.05)
            except (EOFError, OSError):
                pass
        threading.Thread(target=output, daemon=True).start()
        return True

    def check_global_request(self, kind, msg):
        if kind in ("keepalive@openssh.com", "keepalive@libssh2.org"):
            self.keepalives += 1
            return True
        return False


def run_case(binary, case):
    fixture = Fixture(case)
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    port = listener.getsockname()[1]
    channels = []

    def serve():
        client, _ = listener.accept()
        transport = paramiko.Transport(client)
        # The bundled libssh2 predates RSA SHA-2 host-key negotiation. Permit
        # SHA-1 only in this loopback fixture; production policy is unchanged.
        transport.get_security_options().key_types = ("ssh-rsa",)
        fixture.transport = transport
        transport.add_server_key(HOST_KEY)
        try:
            transport.start_server(server=fixture)
            while transport.is_active() and not fixture.stop.is_set():
                channel = transport.accept(0.1)
                if channel:
                    channels.append(channel)
        except EOFError:
            pass
        finally:
            transport.close()

    worker = threading.Thread(target=serve, daemon=True)
    worker.start()
    try:
        subprocess.run([str(binary), str(port), case], check=True, timeout=15)
        assert not fixture.shell_inputs, "Maintenance wrote into the interactive shell"
        if case in ("responsive", "refused", "resume-unresponsive"):
            assert fixture.keepalives > 0, "No keepalive reached the SSH server"
            assert fixture.channels >= 3, "Repeated check did not make a fresh round trip"
    finally:
        fixture.stop.set()
        if fixture.transport:
            fixture.transport.close()
        listener.close()
        worker.join(timeout=2)


with tempfile.TemporaryDirectory(prefix="nmssh-maintenance-") as temp:
    scratch = pathlib.Path(temp) / "build"
    subprocess.run(["swift", "build", "--package-path", str(ROOT), "--scratch-path", str(scratch)], check=True)
    products = pathlib.Path(subprocess.check_output([
        "swift", "build", "--package-path", str(ROOT), "--scratch-path", str(scratch), "--show-bin-path"
    ], text=True).strip())
    binary = pathlib.Path(temp) / "maintenance-test"
    subprocess.run([
        "xcrun", "clang", "-fobjc-arc", "-framework", "Foundation", "-framework", "CFNetwork",
        "-I", str(ROOT / "NMSSH"), "-I", str(products / "include"),
        str(pathlib.Path(__file__).with_name("ConnectionMaintenance.m")),
        str(products / "libNMSSH.a"), str(products / "libssh2.a"), "-lz", "-o", str(binary)
    ], check=True)
    for case in ("responsive", "refused", "unresponsive", "disconnected", "remote-disconnect", "resume-unresponsive"):
        run_case(binary, case)
