# Integration Tests (labgrid)

Hardware-in-the-loop tests that run on the host (master) against the
BeagleBone Black (slave) via SSH.

## Setup

```bash
# Create a Python venv (one-time)
python3 -m venv tests/.venv
source tests/.venv/bin/activate
pip install -r tests/requirements.txt
```

## Configuration

Edit `env.yaml` to match your BBB:

```yaml
targets:
  main:
    resources:
      - NetworkService:
          address: 192.168.1.100    # ← your BBB IP
          username: root
    drivers:
      - SSHDriver:
          keyfile: ""               # ← path to SSH key, or "" for agent/password
```

## Running Tests

```bash
source tests/.venv/bin/activate

# Run all tests
pytest tests/ --lg-env tests/env.yaml -v

# Run a specific test file
pytest tests/test_systemd.py --lg-env tests/env.yaml -v

# Run a specific test class
pytest tests/test_systemd.py::TestNtpdService --lg-env tests/env.yaml -v

# Run a single test
pytest tests/test_systemd.py::TestSystemdInit::test_pid1_is_systemd --lg-env tests/env.yaml -v
```

## Test Structure

- `conftest.py` — labgrid fixtures (`shell`, `systemctl`)
- `env.yaml` — target environment (SSH to BBB)
- `test_systemd.py` — systemd init, services, journal, udev, cgroups

## Adding New Tests

When adding a feature, create a test file `tests/test_<feature>.py`:

```python
def test_my_feature(shell):
    stdout, _, rc = shell.run("some-command")
    assert rc == 0
```

The `shell` fixture (from `conftest.py`) provides an SSH session to the BBB.
