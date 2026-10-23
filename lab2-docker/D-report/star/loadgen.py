"""Простой генератор нагрузки без зависимостей.

Использование: python loadgen.py URL [ПОТОКИ=50] [СЕКУНДЫ=30]
Печатает число успешных ответов, ошибок по типам, rps и перцентили задержки.
"""
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import Counter

url = sys.argv[1]
threads = int(sys.argv[2]) if len(sys.argv) > 2 else 50
duration = float(sys.argv[3]) if len(sys.argv) > 3 else 30

lock = threading.Lock()
latencies = []
errors = Counter()
deadline = time.monotonic() + duration


def worker():
    while time.monotonic() < deadline:
        start = time.monotonic()
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                resp.read()
            key = None
        except urllib.error.HTTPError as e:
            key = f"HTTP {e.code}"
        except Exception as e:  # таймаут, сброс соединения и т.п.
            key = type(e).__name__
        elapsed = time.monotonic() - start
        with lock:
            if key is None:
                latencies.append(elapsed)
            else:
                errors[key] += 1


pool = [threading.Thread(target=worker) for _ in range(threads)]
t0 = time.monotonic()
for t in pool:
    t.start()
for t in pool:
    t.join()
total = time.monotonic() - t0

latencies.sort()


def pct(p):
    return latencies[min(len(latencies) - 1, int(len(latencies) * p))] * 1000


print(f"url={url} threads={threads} duration={total:.1f}s")
print(f"ok={len(latencies)} errors={sum(errors.values())} rps={len(latencies) / total:.1f}")
if latencies:
    print(f"latency ms: p50={pct(0.50):.0f} p95={pct(0.95):.0f} p99={pct(0.99):.0f} max={latencies[-1] * 1000:.0f}")
for k, v in errors.most_common():
    print(f"  error {k}: {v}")
