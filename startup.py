"""One responsive MP4 introduction using a bounded FFmpeg frame queue."""

import logging
from pathlib import Path
from queue import Queue, Empty, Full
from threading import Event, Thread
from time import perf_counter
import pygame
from identity import fit_image

VIDEO = Path(__file__).resolve().parent / "content" / "px" / "gridlock_startup_storyboard.mp4"
log = logging.getLogger(__name__)


def play_startup(screen, clock, path=VIDEO, reader_factory=None):
    """Return False on window close; missing/broken media falls through to menu.

    Decode off the UI thread, hold at most three queued frames, and preserve
    every decoded frame. Keyboard/mouse events never skip the introduction.
    """
    path = Path(path)
    if not path.is_file():
        log.warning("Gridlock startup video missing: %s", path)
        return True
    queue = Queue(maxsize=3)
    stop = Event()

    def send(item):
        while not stop.is_set():
            try:
                queue.put(item, timeout=0.05)
                return
            except Full:
                continue

    def decode():
        reader = None
        try:
            factory = reader_factory
            if factory is None:
                import imageio_ffmpeg
                factory = imageio_ffmpeg.read_frames
            reader = factory(str(path))
            metadata = next(reader)
            fps = metadata.get("fps") or 20.0
            for index, frame in enumerate(reader):
                if stop.is_set():
                    break
                send((index, frame, metadata["size"], fps))
        except Exception as error:
            log.warning("Gridlock startup video could not be decoded: %s", error)
        finally:
            if reader is not None:
                reader.close()
            send(None)

    worker = Thread(target=decode, name="gridlock-startup", daemon=True)
    worker.start()
    screen.fill((7, 8, 12))
    pygame.display.flip()
    elapsed, pending, last_end = 0.0, None, None
    started, finished = False, False
    last_received = perf_counter()
    try:
        while True:
            dt = clock.tick(60) / 1000.0
            if any(event.type == pygame.QUIT for event in pygame.event.get()):
                return False
            if started:
                elapsed += dt
            if pending is None and not finished:
                try:
                    pending = queue.get_nowait()
                    last_received = perf_counter()
                    if pending is None:
                        finished = True
                except Empty:
                    if perf_counter() - last_received > 5:
                        log.warning("Gridlock startup decoder stalled; continuing to menu")
                        return True
            if pending is not None:
                index, data, size, fps = pending
                if not started:
                    elapsed, started = 0.0, True
                if elapsed >= index / fps:
                    frame = pygame.image.frombuffer(data, size, "RGB").convert()
                    frame = fit_image(frame, screen.get_size())
                    screen.fill((7, 8, 12))
                    screen.blit(frame, frame.get_rect(center=screen.get_rect().center))
                    pygame.display.flip()
                    last_end = (index + 1) / fps
                    pending = None
            if finished and (last_end is None or elapsed >= last_end):
                return True
    finally:
        stop.set()
        worker.join(timeout=1)
