#!/usr/bin/env python3
"""
WhatTheFlux — GUI Installer for Venus OS
"""

import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import threading
import urllib.request
import io
import sys
import time

try:
    import paramiko
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko", "-q"])
    import paramiko

GITHUB_RAW = "https://raw.githubusercontent.com/michaelsuenenspro/WhatTheFlux/main"
DRIVER_FILES = [
    "whattheflux.py",
    "run",
    "whattheflux_webgui.py",
    "run-webgui",
]
APP_DIR = "/data/whattheflux"
SERVICE_DIR = "/service/whattheflux"
WEBGUI_SERVICE_DIR = "/service/whattheflux-webgui"

BG       = "#0f172a"
CARD     = "#1e293b"
BORDER   = "#334155"
TEXT     = "#f1f5f9"
MUTED    = "#94a3b8"
ACCENT   = "#3b82f6"
SUCCESS  = "#22c55e"
DANGER   = "#ef4444"
FONT     = ("Segoe UI", 10)
FONT_SM  = ("Segoe UI", 9)
FONT_LG  = ("Segoe UI", 13, "bold")
MONO     = ("Consolas", 9)


class InstallerApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("WhatTheFlux — Installer")
        self.geometry("620x780")
        self.resizable(False, False)
        self.configure(bg=BG)
        self._build_ui()

    def _build_ui(self):
        # Header
        hdr = tk.Frame(self, bg=CARD, pady=16)
        hdr.pack(fill="x")
        tk.Label(hdr, text="⚡  WhatTheFlux Installer", font=FONT_LG,
                 bg=CARD, fg=TEXT).pack()
        tk.Label(hdr, text="for Victron Venus OS", font=FONT_SM,
                 bg=CARD, fg=MUTED).pack()

        # Form
        form = tk.Frame(self, bg=BG, padx=24, pady=16)
        form.pack(fill="x")

        self._section(form, "Venus OS GX")
        self.gx_ip       = self._field(form, "GX IP address",              "192.168.1.10")
        self.ssh_user    = self._field(form, "SSH user",                   "root")
        self.ssh_pass    = self._field(form, "SSH password (leave empty if none)", "", show="*")

        self._section(form, "Alfen charger")
        self.alfen_ip    = self._field(form, "Alfen IP address",           "192.168.1.122")
        self.max_current = self._field(form, "Maximum charging current (A)", "23")
        self.soc_min     = self._field(form, "Minimum battery SOC (%)",    "30")
        self.dev_inst    = self._field(form, "Device instance",            "42")

        self._section(form, "Options")
        self.webgui_var = tk.BooleanVar(value=True)
        chk = tk.Checkbutton(form, text="Install web GUI (accessible on port 8080)",
                              variable=self.webgui_var, bg=BG, fg=TEXT,
                              selectcolor=CARD, activebackground=BG,
                              activeforeground=TEXT, font=FONT)
        chk.pack(anchor="w", pady=(0, 8))

        # Install button
        btn_frame = tk.Frame(self, bg=BG, padx=24)
        btn_frame.pack(fill="x")
        self.btn = tk.Button(btn_frame, text="Install",
                             command=self._start_install,
                             bg=ACCENT, fg="white", font=("Segoe UI", 11, "bold"),
                             relief="flat", cursor="hand2",
                             padx=20, pady=10, bd=0)
        self.btn.pack(fill="x", pady=(0, 16))

        # Progress bar
        self.progress = ttk.Progressbar(self, mode="indeterminate")
        self.progress.pack(fill="x", padx=24, pady=(0, 8))

        # Log output
        log_frame = tk.Frame(self, bg=BG, padx=24, pady=0)
        log_frame.pack(fill="both", expand=True)
        tk.Label(log_frame, text="Log", font=FONT_SM, bg=BG, fg=MUTED).pack(anchor="w")
        self.log = scrolledtext.ScrolledText(log_frame, bg=CARD, fg=TEXT,
                                             font=MONO, relief="flat",
                                             bd=0, height=14,
                                             state="disabled")
        self.log.pack(fill="both", expand=True, pady=(4, 16))
        self.log.tag_config("ok",  foreground=SUCCESS)
        self.log.tag_config("err", foreground=DANGER)
        self.log.tag_config("dim", foreground=MUTED)

    def _section(self, parent, title):
        tk.Label(parent, text=title.upper(), font=("Segoe UI", 8, "bold"),
                 bg=BG, fg=MUTED).pack(anchor="w", pady=(12, 2))
        tk.Frame(parent, bg=BORDER, height=1).pack(fill="x", pady=(0, 8))

    def _field(self, parent, label, default, show=""):
        tk.Label(parent, text=label, font=FONT_SM, bg=BG, fg=MUTED).pack(anchor="w")
        var = tk.StringVar(value=default)
        entry = tk.Entry(parent, textvariable=var, bg=CARD, fg=TEXT,
                         insertbackground=TEXT, relief="flat",
                         font=FONT, bd=6, show=show)
        entry.pack(fill="x", pady=(2, 8))
        return var

    def _log(self, msg, tag=""):
        self.log.configure(state="normal")
        self.log.insert("end", msg + "\n", tag)
        self.log.see("end")
        self.log.configure(state="disabled")
        self.update_idletasks()

    def _start_install(self):
        # Basic validation
        if not self.gx_ip.get().strip():
            messagebox.showerror("Error", "GX IP address is required.")
            return
        if not self.alfen_ip.get().strip():
            messagebox.showerror("Error", "Alfen IP address is required.")
            return

        self.btn.configure(state="disabled", text="Installing...")
        self.progress.start(10)
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")

        thread = threading.Thread(target=self._install, daemon=True)
        thread.start()

    def _install(self):
        try:
            self._do_install()
        except Exception as e:
            self._log(f"\n✗ Error: {e}", "err")
        finally:
            self.progress.stop()
            self.btn.configure(state="normal", text="Install")

    def _do_install(self):
        gx_ip    = self.gx_ip.get().strip()
        user     = self.ssh_user.get().strip() or "root"
        password = self.ssh_pass.get()
        alfen_ip = self.alfen_ip.get().strip()
        max_a    = self.max_current.get().strip() or "23"
        soc      = self.soc_min.get().strip() or "30"
        dev      = self.dev_inst.get().strip() or "42"
        webgui   = self.webgui_var.get()

        # 1. Download files from GitHub
        self._log("Downloading files from GitHub...", "dim")
        files_data = {}
        for fname in DRIVER_FILES:
            if not webgui and fname in ("whattheflux_webgui.py", "run-webgui"):
                continue
            self._log(f"  ↓ {fname}", "dim")
            url = f"{GITHUB_RAW}/{fname}"
            try:
                with urllib.request.urlopen(url, timeout=15) as r:
                    files_data[fname] = r.read()
            except Exception as e:
                raise RuntimeError(f"Download failed for {fname}: {e}")
        self._log("✓ Files downloaded", "ok")

        # 2. SSH connection
        self._log(f"\nConnecting to {gx_ip}...", "dim")
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            ssh.connect(gx_ip, username=user,
                        password=password if password else None,
                        timeout=10,
                        allow_agent=True,
                        look_for_keys=True)
        except paramiko.AuthenticationException:
            raise RuntimeError("Authentication failed — check username/password.")
        except Exception as e:
            raise RuntimeError(f"Connection failed: {e}")
        self._log("✓ Connected", "ok")

        sftp = ssh.open_sftp()

        def run(cmd):
            _, stdout, stderr = ssh.exec_command(cmd)
            out = stdout.read().decode().strip()
            err = stderr.read().decode().strip()
            return out, err

        # 3. Create app directory
        self._log(f"\nCreating directory: {APP_DIR}", "dim")
        run(f"mkdir -p {APP_DIR}")

        # 4. Upload files via SFTP
        self._log("Uploading files...", "dim")
        for fname, data in files_data.items():
            remote = f"{APP_DIR}/{fname}"
            self._log(f"  ↑ {fname}", "dim")
            with sftp.open(remote, "wb") as f:
                f.write(data)
        self._log("✓ Files uploaded", "ok")

        # 5. Create config (only if it doesn't exist yet)
        self._log("\nWriting configuration...", "dim")
        out, _ = run(f"test -f {APP_DIR}/config.ini && echo exists")
        if "exists" in out:
            self._log("  Existing config.ini kept unchanged", "dim")
        else:
            config_content = f"""[alfen]
ip = {alfen_ip}
port = 502
unit_id = 1

[venus]
device_instance = {dev}
custom_name = WhatTheFlux
position = 0
poll_ms = 5000

[charging]
min_current = 6
max_current = {max_a}
manual_current = 16
manual_phases = 3
default_mode = 1
default_ev_priority = 0
battery_reserve_charge_w = 300

[schedule]
current = 16
phases = 3
start_hour = 22
end_hour = 6

[auto]
export_start_w = 1400
phase3_start_w = 5000
phase3_stop_w = 3800
grid_import_limit_w = 200
battery_discharge_limit_w = -200
battery_hard_discharge_w = -800
soc_min = {soc}
phase_switch_debounce_s = 120

[dbus_services]
pv_autodetect = true

[registers]
set_current = 1210
phase_switch = 1215

[logging]
file = /var/log/whattheflux.log
level = INFO
"""
            with sftp.open(f"{APP_DIR}/config.ini", "w") as f:
                f.write(config_content)
            self._log("✓ Configuration written", "ok")

        # 6. Permissions
        self._log("\nSetting permissions...", "dim")
        run(f"chmod +x {APP_DIR}/whattheflux.py")
        run(f"chmod +x {APP_DIR}/run")
        if webgui:
            run(f"chmod +x {APP_DIR}/run-webgui")
            run(f"sed -i 's/whattheflux_42/whattheflux_{dev}/g' {APP_DIR}/whattheflux_webgui.py")

        # 7. Driver service
        self._log("Creating driver service...", "dim")
        run(f"svc -d {SERVICE_DIR} 2>/dev/null; rm -f {SERVICE_DIR}")
        run(f"ln -s {APP_DIR} {SERVICE_DIR}")
        time.sleep(1)
        run(f"svc -u {SERVICE_DIR}")
        self._log("✓ Driver service started", "ok")

        # 8. Web GUI service
        if webgui:
            self._log("Creating web GUI service...", "dim")
            run(f"mkdir -p {WEBGUI_SERVICE_DIR}")
            run(f"ln -sf {APP_DIR}/run-webgui {WEBGUI_SERVICE_DIR}/run")
            time.sleep(1)
            run(f"svc -u {WEBGUI_SERVICE_DIR}")
            self._log("✓ Web GUI service started", "ok")

        # 9. Verify
        self._log("\nChecking service status...", "dim")
        time.sleep(3)
        out, _ = run(f"svstat {SERVICE_DIR}")
        self._log(f"  {out}", "dim")

        sftp.close()
        ssh.close()

        self._log("\n" + "="*48, "ok")
        self._log("✓ Installation complete!", "ok")
        self._log("="*48, "ok")
        self._log(f"\nLogs:  tail -f /var/log/whattheflux.log")
        if webgui:
            self._log(f"GUI:   http://{gx_ip}:8080")

        messagebox.showinfo(
            "Installation complete",
            f"Driver installed and running.\n\n"
            + (f"Web GUI: http://{gx_ip}:8080\n\n" if webgui else "")
            + "View logs via SSH:\ntail -f /var/log/whattheflux.log"
        )


if __name__ == "__main__":
    app = InstallerApp()
    app.mainloop()
