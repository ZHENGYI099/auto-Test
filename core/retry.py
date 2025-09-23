import time
from typing import Callable, TypeVar, Any

T = TypeVar('T')

def retry(fn: Callable[[], T], attempts: int = 3, backoff: float = 1.0, factor: float = 2.0) -> T:
    last_exc: Exception | None = None
    delay = backoff
    for _ in range(attempts):
        try:
            return fn()
        except Exception as e:  # pragma: no cover
            last_exc = e
            time.sleep(delay)
            delay *= factor
    assert last_exc is not None
    raise last_exc
