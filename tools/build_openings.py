#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Builds Scachs/Resources/openings.tsv from the CC0 lichess-org/chess-openings tables.

    python3 -I tools/build_openings.py [--tables .cache/openings] [--out Scachs/Resources/openings.tsv]

Standard library only, so the rules live here: a small board that replays the SAN lines.
The output has one row per position reached on any line, sorted by EPD: `epd<TAB>eco<TAB>name`.
A row with an empty name is book but unnamed: a prefix of a longer named line.
The EPD follows Position.epd: the en passant square is listed only if a capture there is legal.
"""
import argparse
import glob
import os
import re
import sys

KNIGHT = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
KING = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
ROOK = [(1, 0), (-1, 0), (0, 1), (0, -1)]
BISHOP = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
SLIDERS = {"R": ROOK, "B": BISHOP, "Q": ROOK + BISHOP}
START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
SAN = re.compile(r"^([NBRQK]?)([a-h]?)([1-8]?)x?([a-h][1-8])(?:=([NBRQ]))?[+#]?$")


def on_board(file, rank):
    return 0 <= file < 8 and 0 <= rank < 8


class Board:
    def __init__(self):
        self.squares = [None] * 64
        for rank, row in enumerate(reversed(START.split("/"))):
            file = 0
            for char in row:
                if char.isdigit():
                    file += int(char)
                else:
                    self.squares[rank * 8 + file] = char
                    file += 1
        self.white = True
        self.castling = set("KQkq")
        self.ep = None

    def copy(self):
        other = Board.__new__(Board)
        other.squares = self.squares[:]
        other.white = self.white
        other.castling = set(self.castling)
        other.ep = self.ep
        return other

    def own(self, piece, white):
        return piece is not None and piece.isupper() == white

    def attacked(self, square, by_white):
        file, rank = square % 8, square // 8
        def at(f, r):
            return self.squares[r * 8 + f] if on_board(f, r) else None
        pawn_rank = rank - 1 if by_white else rank + 1
        pawn = "P" if by_white else "p"
        if at(file - 1, pawn_rank) == pawn or at(file + 1, pawn_rank) == pawn:
            return True
        knight, king = ("N", "K") if by_white else ("n", "k")
        if any(at(file + df, rank + dr) == knight for df, dr in KNIGHT):
            return True
        if any(at(file + df, rank + dr) == king for df, dr in KING):
            return True
        for directions, kinds in ((ROOK, "RQ"), (BISHOP, "BQ")):
            wanted = kinds if by_white else kinds.lower()
            for df, dr in directions:
                f, r = file + df, rank + dr
                while on_board(f, r):
                    piece = self.squares[r * 8 + f]
                    if piece is not None:
                        if piece in wanted:
                            return True
                        break
                    f, r = f + df, r + dr
        return False

    def pseudo_moves(self):
        moves = []
        for square, piece in enumerate(self.squares):
            if not self.own(piece, self.white):
                continue
            file, rank = square % 8, square // 8
            kind = piece.upper()
            if kind == "P":
                step = 1 if self.white else -1
                forward = square + 8 * step
                if self.squares[forward] is None:
                    self.add_pawn(moves, square, forward)
                    if rank == (1 if self.white else 6) and self.squares[forward + 8 * step] is None:
                        moves.append((square, forward + 8 * step, None))
                for df in (-1, 1):
                    if on_board(file + df, rank + step):
                        target = (rank + step) * 8 + file + df
                        if self.own(self.squares[target], not self.white) or target == self.ep:
                            self.add_pawn(moves, square, target)
            elif kind in SLIDERS:
                for df, dr in SLIDERS[kind]:
                    f, r = file + df, rank + dr
                    while on_board(f, r):
                        target = self.squares[r * 8 + f]
                        if not self.own(target, self.white):
                            moves.append((square, r * 8 + f, None))
                        if target is not None:
                            break
                        f, r = f + df, r + dr
            else:
                for df, dr in KNIGHT if kind == "N" else KING:
                    if on_board(file + df, rank + dr) and not self.own(self.squares[(rank + dr) * 8 + file + df], self.white):
                        moves.append((square, (rank + dr) * 8 + file + df, None))
        return moves

    def add_pawn(self, moves, source, target):
        if target // 8 in (0, 7):
            moves.extend((source, target, kind) for kind in "QRBN")
        else:
            moves.append((source, target, None))

    def apply(self, move):
        source, target, promotion = move
        next_board = self.copy()
        squares = next_board.squares
        piece = squares[source]
        kind = piece.upper()
        if kind == "P" and target == self.ep:
            squares[target + (-8 if self.white else 8)] = None
        squares[source], squares[target] = None, piece
        if promotion:
            squares[target] = promotion if self.white else promotion.lower()
        if kind == "K" and abs(target - source) == 2:
            rook_from, rook_to = (target + 1, target - 1) if target > source else (target - 2, target + 1)
            squares[rook_to], squares[rook_from] = squares[rook_from], None
        next_board.ep = (source + target) // 2 if kind == "P" and abs(target - source) == 16 else None
        for square, right in ((0, "Q"), (4, "KQ"), (7, "K"), (56, "q"), (60, "kq"), (63, "k")):
            if source == square or target == square:
                next_board.castling -= set(right)
        next_board.white = not self.white
        return next_board

    def king(self, white):
        return self.squares.index("K" if white else "k")

    def legal_moves(self):
        return [m for m in self.pseudo_moves() if not self.leaves_king_attacked(m)] + self.castling_moves()

    def leaves_king_attacked(self, move):
        after = self.apply(move)
        return after.attacked(after.king(self.white), not self.white)

    def castling_moves(self):
        moves = []
        home = 4 if self.white else 60
        rights = "KQ" if self.white else "kq"
        enemy = not self.white
        if self.attacked(home, enemy):
            return moves
        if rights[0] in self.castling and self.squares[home + 1] is None and self.squares[home + 2] is None \
                and not self.attacked(home + 1, enemy) and not self.attacked(home + 2, enemy):
            moves.append((home, home + 2, None))
        if rights[1] in self.castling and all(self.squares[home - i] is None for i in (1, 2, 3)) \
                and not self.attacked(home - 1, enemy) and not self.attacked(home - 2, enemy):
            moves.append((home, home - 2, None))
        return moves

    def move_from_san(self, san):
        if san.rstrip("+#") in ("O-O", "O-O-O"):
            home = 4 if self.white else 60
            target = home + (2 if san.rstrip("+#") == "O-O" else -2)
            return next(m for m in self.castling_moves() if m[1] == target)
        match = SAN.match(san)
        if not match:
            raise ValueError(f"unreadable SAN: {san}")
        kind, from_file, from_rank, target, promotion = match.groups()
        kind = kind or "P"
        target = (int(target[1]) - 1) * 8 + ord(target[0]) - ord("a")
        found = []
        for move in self.legal_moves():
            piece = self.squares[move[0]].upper()
            if piece != kind or move[1] != target or move[2] != promotion:
                continue
            if abs(move[1] - move[0]) == 2 and piece == "K":
                continue
            if from_file and move[0] % 8 != ord(from_file) - ord("a"):
                continue
            if from_rank and move[0] // 8 != int(from_rank) - 1:
                continue
            found.append(move)
        if len(found) != 1:
            raise ValueError(f"SAN {san} matches {len(found)} legal moves")
        return found[0]

    def legal_ep(self):
        if self.ep is None:
            return None
        pawn = "P" if self.white else "p"
        for move in self.pseudo_moves():
            if move[1] == self.ep and self.squares[move[0]] == pawn and not self.leaves_king_attacked(move):
                return self.ep
        return None

    def epd(self):
        rows = []
        for rank in range(7, -1, -1):
            row, empty = "", 0
            for file in range(8):
                piece = self.squares[rank * 8 + file]
                if piece is None:
                    empty += 1
                else:
                    if empty:
                        row += str(empty)
                        empty = 0
                    row += piece
            rows.append(row + (str(empty) if empty else ""))
        castling = "".join(c for c in "KQkq" if c in self.castling) or "-"
        ep = self.legal_ep()
        ep_text = "-" if ep is None else "abcdefgh"[ep % 8] + str(ep // 8 + 1)
        return f"{'/'.join(rows)} {'w' if self.white else 'b'} {castling} {ep_text}"


def replay(pgn):
    board = Board()
    positions = []
    for token in pgn.split():
        if token[0].isdigit():
            continue
        board = board.apply(board.move_from_san(token))
        positions.append(board.epd())
    return positions


def build(tables):
    rows = {}
    named = {}
    collisions = 0
    paths = sorted(glob.glob(os.path.join(tables, "*.tsv")))
    if not paths:
        sys.exit(f"no .tsv tables in {tables}")
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            header = handle.readline().rstrip("\n").split("\t")
            if header[:3] != ["eco", "name", "pgn"]:
                sys.exit(f"unexpected header in {path}: {header}")
            for line in handle:
                eco, name, pgn = line.rstrip("\n").split("\t")[:3]
                positions = replay(pgn)
                for epd in positions:
                    rows.setdefault(epd, ("", ""))
                final = positions[-1]
                # The same position under two names: the shorter line wins, then the sort order.
                candidate = (len(positions), eco, name)
                if final in named:
                    collisions += 1
                    if candidate >= named[final]:
                        continue
                named[final] = candidate
                rows[final] = (eco, name)
    return rows, len(named), collisions


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tables", default=".cache/openings")
    parser.add_argument("--out", default="Scachs/Resources/openings.tsv")
    args = parser.parse_args()
    rows, named, collisions = build(args.tables)
    with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
        for epd in sorted(rows):
            eco, name = rows[epd]
            handle.write(f"{epd}\t{eco}\t{name}\n")
    print(f"{args.out}: {len(rows)} book positions, {named} named, {collisions} name collisions")


if __name__ == "__main__":
    main()
