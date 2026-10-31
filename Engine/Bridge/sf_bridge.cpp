// SPDX-License-Identifier: GPL-3.0-or-later
#include "sf_bridge.h"

#include <cstdio>
#include <filesystem>
#include <mutex>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

#include "../Stockfish/src/attacks.h"
#include "../Stockfish/src/engine.h"
#include "../Stockfish/src/evaluate.h"
#include "../Stockfish/src/position.h"
#include "../Stockfish/src/score.h"
#include "../Stockfish/src/search.h"
#include "../Stockfish/src/uci.h"

using namespace Stockfish;

struct sf_engine {
    explicit sf_engine(const std::filesystem::path& binary) :
        engine(binary) {}

    Engine      engine;
    std::string error;

    // Written only while no search runs, read only by the search.
    void*      ctx     = nullptr;
    sf_line_cb on_line = nullptr;
    sf_done_cb on_done = nullptr;
};

namespace {

template<typename... Ts>
struct overload: Ts... {
    using Ts::operator()...;
};
template<typename... Ts>
overload(Ts...) -> overload<Ts...>;

void set_option(Engine& engine, const std::string& name, const std::string& value) {
    std::istringstream is("name " + name + " value " + value);
    engine.get_options().setoption(is);
}

std::vector<std::string> split(const char* text) {
    std::vector<std::string> tokens;
    std::istringstream       is(text ? text : "");
    for (std::string token; is >> token;)
        tokens.push_back(token);
    return tokens;
}

void fill_score(sf_line& line, const Score& score) {
    score.visit(overload{
      [&](Score::InternalUnits units) {
          line.score_kind  = SF_SCORE_CP;
          line.score_value = units.value;
      },
      [&](Score::Mate mate) {
          line.score_kind  = SF_SCORE_MATE;
          line.score_value = mate.plies;
      },
      // Unreachable without tablebases. Same mapping as UCIEngine::format_score.
      [&](Score::Tablebase tb) {
          line.score_kind  = SF_SCORE_CP;
          line.score_value = (tb.win ? 20000 : -20000) - tb.plies;
      },
    });
}

}  // namespace

extern "C" {

const char* sf_net_name(void) { return EvalFileDefaultName; }

sf_engine* sf_create(const char* net_dir, int threads, int hash_mb) {
    static std::once_flag once;
    std::call_once(once, [] {
        Attacks::init();
        Position::init();
    });

    // The net is found next to the "binary". The file itself need not exist.
    auto* handle = new sf_engine(std::filesystem::path(net_dir) / "stockfish");
    auto& engine = handle->engine;

    // Under -fno-exceptions calling an empty std::function aborts, so every one is set.
    // onIter stays silent until 10M nodes on the main thread, so a missing one only shows late.
    engine.set_on_start([] {});
    engine.set_on_iter([](const Engine::InfoIter&) {});
    engine.set_on_verify_network([](std::string_view) {});
    engine.set_on_update_no_moves([handle](const Engine::InfoShort& info) {
        sf_line line{};
        line.multipv = 1;
        line.depth   = info.depth;
        line.pv      = "";
        fill_score(line, info.score);
        handle->on_line(handle->ctx, &line);
    });
    engine.set_on_update_full([handle](const Engine::InfoFull& info) {
        sf_line line{};
        line.multipv  = int(info.multiPV);
        line.depth    = info.depth;
        line.seldepth = info.selDepth;
        line.hashfull = info.hashfull;
        line.nodes    = info.nodes;
        line.nps      = info.nps;
        line.time_ms  = info.timeMs;
        fill_score(line, info.score);

        std::string wdl(info.wdl);
        std::sscanf(wdl.c_str(), "%d %d %d", &line.wdl_win, &line.wdl_draw, &line.wdl_loss);

        std::string pv(info.pv);
        line.pv = pv.c_str();
        handle->on_line(handle->ctx, &line);
    });
    engine.set_on_bestmove([handle](std::string_view best, std::string_view) {
        std::string move(best);
        handle->on_done(handle->ctx, move.c_str());
    });

    // Threads first: changing it rebuilds the pool and reallocates the hash.
    set_option(engine, "Threads", std::to_string(threads));
    set_option(engine, "Hash", std::to_string(hash_mb));
    set_option(engine, "UCI_ShowWDL", "true");
    return handle;
}

void sf_destroy(sf_engine* handle) {
    handle->engine.stop();
    handle->engine.wait_for_search_finished();
    delete handle;
}

int sf_go(sf_engine* handle, const char* fen, const char* moves, const char* searchmoves,
          int multipv, uint64_t nodes, int64_t movetime_ms,
          void* ctx, sf_line_cb on_line, sf_done_cb on_done) {
    auto& engine = handle->engine;
    engine.wait_for_search_finished();

    handle->error.clear();
    if (auto error = engine.set_position(fen, split(moves)))
    {
        handle->error = error->what();
        // The failed set left the position zeroed, and go has no guard against that.
        engine.set_position(StartFEN, {});
        return 0;
    }

    set_option(engine, "MultiPV", std::to_string(multipv));

    handle->ctx     = ctx;
    handle->on_line = on_line;
    handle->on_done = on_done;

    Search::LimitsType limits;
    limits.startTime   = now();
    limits.nodes       = nodes;
    limits.movetime    = movetime_ms;
    limits.searchmoves = split(searchmoves);

    engine.go(limits);
    return 1;
}

const char* sf_error(const sf_engine* handle) { return handle->error.c_str(); }

void sf_stop(sf_engine* handle) { handle->engine.stop(); }

void sf_wait(sf_engine* handle) { handle->engine.wait_for_search_finished(); }

void sf_clear(sf_engine* handle) { handle->engine.search_clear(); }
}
