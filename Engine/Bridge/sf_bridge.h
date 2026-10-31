// SPDX-License-Identifier: GPL-3.0-or-later
// Flat C API over Stockfish::Engine, the only thing Swift sees of the engine.
//
// Not thread-safe: call everything from one serial context, except sf_stop.
// sf_create, sf_clear, sf_wait and sf_destroy block.
#ifndef SF_BRIDGE_H
#define SF_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sf_engine sf_engine;

enum { SF_SCORE_CP = 0, SF_SCORE_MATE = 1 };

typedef struct {
    int multipv;      // 1-based
    int depth;        // 0 when the root has no legal moves
    int seldepth;
    int score_kind;   // SF_SCORE_CP or SF_SCORE_MATE
    int score_value;  // side to move's view: centipawns, or plies to mate (negative: being mated)
    int wdl_win;      // per mille, side to move's view
    int wdl_draw;
    int wdl_loss;
    int hashfull;
    uint64_t nodes;
    uint64_t nps;
    uint64_t time_ms;
    const char* pv;   // space separated UCI moves, valid only during the callback
} sf_line;

// Both fire on a search thread. Copy what you keep, never call back into the engine.
typedef void (*sf_line_cb)(void* ctx, const sf_line* line);
typedef void (*sf_done_cb)(void* ctx, const char* bestmove);  // always the last call of a search

// File name of the net this build expects, for example nn-1a298aa575a0.nnue.
const char* sf_net_name(void);

// net_dir must hold a verified net: a missing or corrupt one ends the process on the first go.
sf_engine* sf_create(const char* net_dir, int threads, int hash_mb);
void       sf_destroy(sf_engine* engine);

// Starts a search and returns at once. Returns 0 on a rejected position, with the
// reason in sf_error and the engine back on the start position. moves and searchmoves
// are space separated UCI moves, searchmoves may be NULL. nodes and movetime_ms: 0 means no limit.
int sf_go(sf_engine* engine, const char* fen, const char* moves, const char* searchmoves,
          int multipv, uint64_t nodes, int64_t movetime_ms,
          void* ctx, sf_line_cb on_line, sf_done_cb on_done);

const char* sf_error(const sf_engine* engine);  // valid until the next sf_go

void sf_stop(sf_engine* engine);   // any thread, returns at once
void sf_wait(sf_engine* engine);
void sf_clear(sf_engine* engine);  // hash and histories, between games

#ifdef __cplusplus
}
#endif

#endif
