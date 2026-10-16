#!/usr/bin/env python3
"""Штрихи цифр для MorphText: assets/digits/Digits.js.

У Neofolia и JetBrains Mono штрих почти одной толщины, поэтому символ —
это осевые линии (скелет), обведённые круглой кистью. Морфим не контуры,
а эти линии, и рисуем их той же кистью: толщина одинакова на каждом
кадре. Скрипт делает всё сам:
  1. растеризует глиф и берёт его скелет (medial axis), толщину кисти —
     по медиане расстояния до края вдоль скелета;
  2. режет скелет на штрихи: обрезает «усы» у углов, склеивает рёбра
     через развилки по прямизне;
  3. для каждой пары символов подбирает, какой штрих во что перетекает
     (венгерский алгоритм), с какой точки начинать петлю и в какую
     сторону идти; лишние штрихи стягиваются в точку на другом символе.

Запуск (нужны fonttools, numpy, scipy, pillow):
  nix shell --impure --expr 'with import <nixpkgs> {}; python3.withPackages (p: [ p.fonttools p.numpy p.scipy p.pillow ])' \\
    -c python3 tools/digits.py <каталог JetBrainsMonoNerdFont-*.ttf> [--sheet out.png]
Neofolia берётся из assets/fonts.
"""
import itertools
import json
import os
import sys

import numpy as np
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont
from PIL import Image, ImageChops, ImageDraw
from scipy.ndimage import distance_transform_edt, label
from scipy.optimize import linear_sum_assignment

CHARS = "0123456789:%.,+-−°/ "
RES = 360            # высота растра рамки символа, px
N = 32               # точек на штрих

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class FlatPen(BasePen):
    def __init__(self, glyphSet):
        super().__init__(glyphSet)
        self.contours, self.cur = [], []

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        for i in range(1, 17):
            t = i / 16
            a = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
            self.cur.append(tuple(sum(w * q[k] for w, q in zip(a, (p0, p1, p2, p3))) for k in (0, 1)))

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        for i in range(1, 13):
            t = i / 12
            a = (1 - t) ** 2, 2 * (1 - t) * t, t ** 2
            self.cur.append(tuple(sum(w * q[k] for w, q in zip(a, (p0, p1, p2))) for k in (0, 1)))

    def _closePath(self):
        if len(self.cur) > 2:
            self.contours.append(self.cur)
        self.cur = []

    _endPath = _closePath


# ===== Скелет → штрихи =====

NB = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


def neighbours(sk, p):
    y, x = p
    return [(y + dy, x + dx) for dy, dx in NB
            if 0 <= y + dy < sk.shape[0] and 0 <= x + dx < sk.shape[1] and sk[y + dy, x + dx]]


def skeletonize(m):
    """Скелет Zhang–Suen: по очереди срезаем граничные пиксели, которые
    не концы и не мосты, пока срезается."""
    img = np.pad(m.astype(np.uint8), 1)
    while True:
        changed = False
        for step in (0, 1):
            P = [np.roll(np.roll(img, -dy, 0), -dx, 1) for dy, dx in RING]
            # P2..P9 по часовой от верхнего: верх, верх-право, право, ...
            p2, p3, p4, p5, p6, p7, p8, p9 = P[1], P[2], P[3], P[4], P[5], P[6], P[7], P[0]
            seq = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
            B = sum(seq[:8])
            A = sum(((seq[i] == 0) & (seq[i + 1] == 1)).astype(np.uint8) for i in range(8))
            if step == 0:
                c = (p2 * p4 * p6 == 0) & (p4 * p6 * p8 == 0)
            else:
                c = (p2 * p4 * p8 == 0) & (p2 * p6 * p8 == 0)
            kill = (img == 1) & (B >= 2) & (B <= 6) & (A == 1) & c
            if kill.any():
                img[kill] = 0
                changed = True
        if not changed:
            return img[1:-1, 1:-1].astype(bool)


RING = [(-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1)]


def thin(sk):
    """Минимальный 8-связный скелет: убираем пиксели «ступенек», без которых
    соседи и так связаны. Иначе у обычной линии лишние соседи, и она
    выглядит как цепочка развилок."""
    sk = sk.copy()
    h, w = sk.shape
    changed = True
    while changed:
        changed = False
        for y, x in zip(*np.nonzero(sk)):
            ring = [0 < y + dy < h - 1 and 0 < x + dx < w - 1 and sk[y + dy, x + dx] for dy, dx in RING]
            if sum(ring) < 2:
                continue                      # конец линии — не трогаем
            # Связны ли соседи без нас: компоненты по кольцу (8-связность)
            on = [i for i in range(8) if ring[i]]
            parent = {i: i for i in on}
            def find(i):
                while parent[i] != i:
                    i = parent[i]
                return i
            for i in on:
                for j in on:
                    if i < j:
                        (ay, ax), (by, bx) = RING[i], RING[j]
                        if max(abs(ay - by), abs(ax - bx)) == 1:
                            parent[find(i)] = find(j)
            if len({find(i) for i in on}) == 1:
                sk[y, x] = False
                changed = True
    return sk


def graph(sk):
    """Рёбра скелета: [(узел, узел, [пиксели])], узлы — концы и развилки
    (смежные пиксели развилки — один узел), плюс петли без узлов."""
    pix = set(zip(*np.nonzero(sk)))
    deg = {p: len(neighbours(sk, p)) for p in pix}
    nodepix = {p for p in pix if deg[p] != 2}
    lab, _ = label(np.isin(np.arange(sk.size).reshape(sk.shape), [p[0] * sk.shape[1] + p[1] for p in nodepix]),
                   structure=np.ones((3, 3)))
    node_of = {p: int(lab[p]) for p in nodepix}
    centre = {}
    for p, n in node_of.items():
        centre.setdefault(n, []).append(p)
    centre = {n: tuple(np.mean(ps, axis=0)) for n, ps in centre.items()}

    edges, seen = [], set()
    for p in nodepix:
        for q in neighbours(sk, p):
            if q in nodepix or (p, q) in seen:
                continue
            path, prev, cur = [p, q], p, q
            while cur not in nodepix:
                nxt = [r for r in neighbours(sk, cur) if r != prev and r not in path]
                if not nxt:
                    break
                prev, cur = cur, nxt[0]
                path.append(cur)
            seen.add((p, q))
            if cur in nodepix:
                seen.add((cur, path[-2]))
            a, b = node_of[p], node_of.get(cur)
            pts = [centre[a]] + path[1:-1] + ([centre[b]] if b is not None else [path[-1]])
            edges.append([a, b, pts])
    # Петли без узлов (как у «0» без перечёркивания)
    rest = pix - {q for e in edges for q in e[2]} - nodepix
    loops = []
    while rest:
        start = next(iter(rest))
        path, prev, cur = [start], None, start
        while True:
            nxt = [r for r in neighbours(sk, cur) if r != prev and r in rest and r not in path[-2:]]
            if not nxt or nxt[0] == start:
                break
            prev, cur = cur, nxt[0]
            path.append(cur)
        rest -= set(path)
        if len(path) > 8:
            loops.append(path)
    return edges, loops, centre


def plen(pts):
    a = np.asarray(pts, float)
    return float(np.sum(np.linalg.norm(np.diff(a, axis=0), axis=1))) if len(a) > 1 else 0.0


def strokes_of(mask):
    """Штрихи глифа (списки точек y, x в px растра), радиус кисти и
    радиусы точек {номер штриха: px} — точки в шрифтах крупнее кисти."""
    dist = distance_transform_edt(mask)
    sk = thin(skeletonize(mask))
    # Жирные точки скелетизация стирает целиком — их подберём ниже
    r = float(np.median(dist[sk])) if sk.any() else 0.0
    edges, loops, centre = graph(sk) if sk.any() else ([], [], {})

    # Усы: короткие рёбра от конца к развилке — артефакты углов
    while True:
        cnt = {}
        for a, b, _ in edges:
            cnt[a] = cnt.get(a, 0) + 1
            if b is not None:
                cnt[b] = cnt.get(b, 0) + 1
        spur = [e for e in edges if (cnt.get(e[0], 0) == 1) != (e[1] is None or cnt.get(e[1], 0) == 1)
                and plen(e[2]) < 1.5 * r and len(edges) > 1]
        if not spur:
            break
        edges.remove(min(spur, key=lambda e: plen(e[2])))

    # Склейка: через узел степени 2 — всегда, через развилку — самые прямые пары
    def direction(pts, at_start):
        a = np.asarray(pts[:6] if at_start else pts[-6:][::-1], float)
        d = a[-1] - a[0]
        return d / (np.linalg.norm(d) + 1e-9)

    changed = True
    while changed:
        changed = False
        ends = {}
        for i, (a, b, _) in enumerate(edges):
            ends.setdefault(a, []).append((i, True))
            if b is not None:
                ends.setdefault(b, []).append((i, False))
        for node, lst in ends.items():
            if len(lst) < 2:
                continue
            best = None
            for (i, si), (j, sj) in itertools.combinations(lst, 2):
                if i == j:
                    continue
                c = float(np.dot(direction(edges[i][2], si), direction(edges[j][2], sj)))
                if len(lst) == 2 or c < -0.5:          # почти продолжение друг друга
                    if best is None or c < best[0]:
                        best = (c, i, si, j, sj)
            if best:
                _, i, si, j, sj = best
                pi = edges[i][2] if not si else edges[i][2][::-1]          # к узлу
                pj = edges[j][2] if sj else edges[j][2][::-1]              # от узла
                ai = edges[i][1] if si else edges[i][0]
                bj = edges[j][1] if sj else edges[j][0]
                merged = [ai, bj, pi + pj[1:]]
                if ai == bj and ai is not None and len(lst) == 2:
                    merged = [None, None, pi + pj[1:]]                    # замкнулось
                for k in sorted((i, j), reverse=True):
                    edges.pop(k)
                edges.append(merged)
                changed = True
                break

    out = []
    for a, b, pts in edges:
        closed = a is None and b is None and np.linalg.norm(np.subtract(pts[0], pts[-1])) < 2.5
        out.append((pts, closed))
    for pts in loops:
        out.append((pts + [pts[0]], True))

    # Точки («:», «.», точка в нуле): скелет круга вырождается, и штриха
    # у такого куска нет — рисуем его штрихом нулевой длины, то есть
    # кругом той же кисти
    lab, n = label(mask, structure=np.ones((3, 3)))
    # Огрызок скелета в пятне (точка, от которой осталась пара пикселей) —
    # тоже точка: штрих убираем, пятно подберём ниже целиком
    out = [(pts, c) for pts, c in out if plen(pts) >= 1.5 * r]
    covered = {int(lab[int(round(y)), int(round(x))]) for pts, _ in out for y, x in pts}
    dots = {}
    for k in range(1, n + 1):
        if k not in covered:
            ys, xs = np.nonzero(lab == k)
            if len(ys) > max(16, r * r):
                c = (float(ys.mean()), float(xs.mean()))
                dots[len(out)] = float(np.sqrt(len(ys) / np.pi))
                out.append(([c, c], False))
    return out, r, dots


def smooth_resample(pts, closed):
    a = np.asarray(pts, float)
    if closed:
        a = a[:-1]
        k = 5
        a = np.array([a[(np.arange(i - k, i + k + 1)) % len(a)].mean(axis=0) for i in range(len(a))])
        a = np.vstack([a, a[:1]])
    elif len(a) > 7:
        k = 3
        b = a.copy()
        for i in range(1, len(a) - 1):
            lo, hi = max(0, i - k), min(len(a), i + k + 1)
            b[i] = a[lo:hi].mean(axis=0)
        a = b
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(a, axis=0), axis=1))])
    if d[-1] == 0:
        return np.repeat(a[:1], N, axis=0)
    t = np.linspace(0, d[-1], N + (1 if closed else 0))[: N]
    return np.stack([np.interp(t, d, a[:, 0]), np.interp(t, d, a[:, 1])], axis=1)


# ===== Сопоставление штрихов двух символов =====

def variants(s, closed):
    """Варианты обхода штриха: прямо/обратно, у петли — ещё и сдвиги начала."""
    if closed:
        for sh in range(0, N, 2):
            r = np.roll(s, -sh, axis=0)
            yield r, (sh, False)
            yield r[::-1], (sh, True)
    else:
        yield s, (0, False)
        yield s[::-1], (0, True)


def dtw(a, b):
    """Выравнивание двух ломаных: пары индексов (i, j), монотонно от начала
    к концу, с минимальной суммой расстояний — точки едут как можно меньше."""
    d = np.linalg.norm(a[:, None] - b[None], axis=2)
    n, m = d.shape
    D = np.full((n + 1, m + 1), np.inf)
    D[0, 0] = 0
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            D[i, j] = d[i - 1, j - 1] + min(D[i - 1, j], D[i, j - 1], D[i - 1, j - 1])
    i, j, path = n, m, []
    while i > 0 and j > 0:
        path.append((i - 1, j - 1))
        k = np.argmin([D[i - 1, j - 1], D[i - 1, j], D[i, j - 1]])
        i, j = (i - 1, j - 1) if k == 0 else (i - 1, j) if k == 1 else (i, j - 1)
    path = np.array(path[::-1], float)
    # Равномерно по ходу выравнивания → N пар дробных индексов
    prog = np.concatenate([[0], np.cumsum(np.abs(np.diff(path, axis=0)).sum(axis=1))])
    t = np.linspace(0, prog[-1], N)
    return np.interp(t, prog, path[:, 0]), np.interp(t, prog, path[:, 1])


def at(s, u):
    """Точка ломаной s по дробному индексу u."""
    i = np.clip(np.floor(u).astype(int), 0, len(s) - 2)
    f = (u - i)[:, None]
    return s[i] * (1 - f) + s[i + 1] * f


def pair_cost(sa, ca, sb, cb, warp):
    """Лучший обход sb под sa: (цена, (сдвиг, обратно), индексы выравнивания).
    Цена — путь точек плюс штраф, если линия в середине перехода короче
    обоих концов: так она не мнётся и не схлопывается в черту."""
    best = (1e18, None, None)
    la, lb = plen(sa), plen(sb)
    for vb, how in variants(sb, cb):
        if warp:
            ua, ub = dtw(sa, vb)
            pa, pb = at(sa, ua), at(vb, ub)
        else:
            ua = ub = None
            pa, pb = sa, vb
        c = float(np.mean(np.linalg.norm(pa - pb, axis=1)))
        c += 0.5 * max(0.0, min(la, lb) - plen((pa + pb) / 2))
        if c < best[0]:
            best = (c, how, (ua, ub))
    return best


def match(A, B, warp=False):
    """A, B: [(точки N×2, замкнут)]. → [(iA | -1, iB | -1, сдвиг, обратно, точка схлопывания)]"""
    na, nb = len(A), len(B)
    n = max(na, nb, 1)
    big = 1e6
    C = np.full((n, n), big)
    how = {}
    allA = np.vstack([s for s, _ in A]) if A else np.zeros((1, 2))
    allB = np.vstack([s for s, _ in B]) if B else np.zeros((1, 2))
    for i, (sa, ca) in enumerate(A):
        for j, (sb, cb) in enumerate(B):
            c, h, w = pair_cost(sa, ca, sb, cb, warp)
            C[i, j] = c
            how[i, j] = (h, w)
    # Схлопывание в точку: путь до ближайшей точки другого символа + штраф
    for i in range(na):
        for j in range(nb, n):
            d = np.linalg.norm(A[i][0][:, None] - allB[None], axis=2).min(axis=1)
            C[i, j] = float(d.mean()) + 25
    for j in range(nb):
        for i in range(na, n):
            d = np.linalg.norm(B[j][0][:, None] - allA[None], axis=2).min(axis=1)
            C[i, j] = float(d.mean()) + 25
    rows, cols = linear_sum_assignment(C)
    res = []
    for i, j in zip(rows, cols):
        if i < na and j < nb:
            (sh, rev), (ua, ub) = how[i, j]
            e = [int(i), int(j), int(sh), bool(rev), None]
            if ua is not None:
                e += [[round(float(v), 2) for v in ua], [round(float(v), 2) for v in ub]]
            res.append(e)
        elif i < na:
            c = A[i][0].mean(axis=0)
            p = allB[np.argmin(np.linalg.norm(allB - c, axis=1))] if B else c
            res.append([int(i), -1, 0, False, [float(p[0]), float(p[1])]])
        elif j < nb:
            c = B[j][0].mean(axis=0)
            p = allA[np.argmin(np.linalg.norm(allA - c, axis=1))] if A else c
            res.append([-1, int(j), 0, False, [float(p[0]), float(p[1])]])
    return res


# ===== Шрифт =====

def build(name, path, sheet=None):
    font = TTFont(path)
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    glyphs = {}
    for ch in CHARS:
        g = cmap.get(ord(ch)) or (cmap.get(ord("-")) if ch == "−" else None)
        if g is None:
            continue
        pen = FlatPen(gs)
        gs[g].draw(pen)
        glyphs[ch] = (pen.contours, gs[g].width)

    pts = [p for c, _ in glyphs.values() for cnt in c for p in cnt]
    asc, desc = font["hhea"].ascent, font["hhea"].descent
    y0, y1 = min(desc, min(p[1] for p in pts)), max(asc, max(p[1] for p in pts))
    x0 = min(0, min(p[0] for p in pts))
    x1 = max(max(w for _, w in glyphs.values()), max(p[0] for p in pts))
    H = y1 - y0
    sc = RES / H
    W = int(np.ceil((x1 - x0) * sc)) + 2

    chars, radii, masks = {}, [], {}
    for ch, (contours, adv) in glyphs.items():
        img = Image.new("1", (W, RES + 2), 0)
        for cnt in contours:
            layer = Image.new("1", img.size, 0)
            ImageDraw.Draw(layer).polygon([((x - x0) * sc + 1, (y1 - y) * sc + 1) for x, y in cnt], fill=1)
            img = ImageChops.logical_xor(img, layer)
        m = np.array(img, bool)
        masks[ch] = m
        strokes, r, dots = strokes_of(m)
        if r:
            radii.append(r)
        # px растра → доли высоты рамки, x от начала символа
        conv = lambda s: np.stack([(s[:, 1] - 1) / RES + x0 / H, (s[:, 0] - 1) / RES], axis=1)
        chars[ch] = {"adv": adv / H, "dots": {i: d / RES for i, d in dots.items()},
                     "strokes": [(conv(smooth_resample(p, c)), c) for p, c in strokes]}
    radius = float(np.median(radii)) / RES

    pairs = {}
    keys = list(chars)
    for a in keys:
        for b in keys:
            if a != b:
                # Цифры с цифрами — с выравниванием (их морф видно чаще всего),
                # остальное — по равным долям длины
                pairs[a + b] = match(chars[a]["strokes"], chars[b]["strokes"], a.isdigit() and b.isdigit())

    if sheet is not None:
        sheet.append((name, chars, masks, radius, x0 / H, W, sc))

    return {
        "radius": radius,
        "height": H / font["head"].unitsPerEm,
        "baseline": y1 / H,
        "chars": {ch: {"adv": round(c["adv"], 4),
                       "strokes": [dict({"closed": bool(cl), "pts": [round(float(v), 4) for v in s.ravel()]},
                                        **({"r": round(c["dots"][i], 4)} if i in c["dots"] else {}))
                                   for i, (s, cl) in enumerate(c["strokes"])]}
                  for ch, c in chars.items()},
        "pairs": pairs,
    }


def draw_sheet(sheet, out):
    rows = []
    for name, chars, masks, radius, ox, W, sc in sheet:
        tiles = []
        for ch, c in chars.items():
            m = masks[ch]
            im = Image.new("RGB", (m.shape[1], m.shape[0]), "#11111b")
            im.paste(Image.new("RGB", im.size, "#45475a"), mask=Image.fromarray((m * 255).astype(np.uint8)))
            d = ImageDraw.Draw(im)
            rr = radius * RES
            for s, closed in c["strokes"]:
                p = [((x - ox) * RES + 1, y * RES + 1) for x, y in s]
                if closed:
                    p.append(p[0])
                d.line(p, fill="#b4637a", width=int(2 * rr), joint="curve")
                for q in (p[0], p[-1]):
                    d.ellipse([q[0] - rr, q[1] - rr, q[0] + rr, q[1] + rr], fill="#f5c2e7")
                d.line(p, fill="#11111b", width=2)
            tiles.append(im.resize((im.width // 3, im.height // 3)))
        row = Image.new("RGB", (sum(t.width for t in tiles), tiles[0].height), "#000")
        x = 0
        for t in tiles:
            row.paste(t, (x, 0)); x += t.width
        rows.append(row)
    s = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows)))
    y = 0
    for r in rows:
        s.paste(r, (0, y)); y += r.height
    s.save(out)


def main():
    args = sys.argv[1:]
    sheet_out = None
    if "--sheet" in args:
        i = args.index("--sheet"); sheet_out = args[i + 1]; del args[i:i + 2]
    mono = args[0] if args else ""
    fonts = {"neofolia": os.path.join(REPO, "assets", "fonts", "Neofolia-Regular.ttf")}
    for name, f in (("mono", "Regular"), ("monoBold", "Bold"), ("monoBoldItalic", "BoldItalic")):
        fonts[name] = os.path.join(mono, "JetBrainsMonoNerdFont-%s.ttf" % f)
    sheet = [] if sheet_out else None
    data = {name: build(name, path, sheet) for name, path in fonts.items()}
    if sheet_out:
        draw_sheet(sheet, sheet_out)
    os.makedirs(os.path.join(REPO, "assets", "digits"), exist_ok=True)
    with open(os.path.join(REPO, "assets", "digits", "Digits.js"), "w") as f:
        f.write(".pragma library\n\n// Сгенерировано tools/digits.py — руками не править\n")
        f.write("const fonts = " + json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")


main()
