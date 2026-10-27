#!/usr/bin/env escript
%%! -noinput
%% Cross-repo wire op-code sync check.
%%
%% The diff op codes in arizona's `include/arizona_wire.hrl` and the effect op
%% codes in `include/arizona_effect.hrl` are hand-copied into this client's
%% `Wire.kt`. A native client skips an unknown op non-strictly, so a renumber or
%% addition on either side drifts silently until a patch or event misfires. This
%% reads the headers of an arizona checkout as the source of truth and fails on
%% any disagreement.
%%
%% Usage: scripts/check_wire.escript <arizona-checkout>
%% The checkout must be compiled (`rebar3 compile`): the set of ops the native
%% backend emits is asked of `arizona_json`, not guessed.
-mode(compile).

main([ArizonaDir]) ->
    add_arizona_ebin(ArizonaDir),
    Canonical = canonical(ArizonaDir),
    sane(Canonical),
    Ops = android(ops),
    Effects = android(effects),
    JsonClient = json_client(ArizonaDir),
    Failures =
        check(~"ops match the native backend", native_backend_ops(Canonical) =:= Ops, {
            native_backend_ops(Canonical), Ops
        }) ++
            check(
                ~"effects are a non-empty subset of the header",
                Effects =/= #{} andalso
                    maps:with(maps:keys(Effects), map_get(effects, Canonical)) =:= Effects,
                {map_get(effects, Canonical), Effects}
            ) ++
            check(
                ~"effects agree with the reference JSON client (e2e/utils/json_client.js)",
                Effects =:= JsonClient,
                {JsonClient, Effects}
            ),
    case Failures of
        [] ->
            io:format("wire codes match ~ts~n", [ArizonaDir]);
        _ ->
            [io:format(standard_error, "FAIL: ~ts~n  expected: ~p~n  actual:   ~p~n", [N, E, A])
             || {N, {E, A}} <- Failures],
            halt(1)
    end;
main(_) ->
    io:format(standard_error, "usage: check_wire.escript <arizona-checkout>~n", []),
    halt(2).

check(_Name, true, _Detail) -> [];
check(Name, false, Detail) -> [{Name, Detail}].

add_arizona_ebin(ArizonaDir) ->
    case filelib:wildcard(filename:join(ArizonaDir, "_build/*/lib/arizona/ebin")) of
        [Ebin | _] ->
            true = code:add_patha(Ebin);
        [] ->
            io:format(standard_error, "~ts is not compiled; run `rebar3 compile` there~n", [
                ArizonaDir
            ]),
            halt(2)
    end.

%% Guard the extraction itself: a broken regex that captures nothing would make
%% every comparison pass trivially (empty == empty).
sane(#{ops := Ops, effects := Effects}) ->
    #{~"TEXT" := 0, ~"LIST_PATCH" := 10} = Ops,
    false = lists:member(3, maps:values(Ops)),
    #{~"PUSH_EVENT" := 0, ~"NAVIGATE" := 10} = Effects,
    true = map_size(Effects) >= 20,
    ok.

canonical(Dir) ->
    #{
        ops => extract(read([Dir, "include", "arizona_wire.hrl"]), ~"OP_([A-Z0-9_]+),\\s*([0-9]+)"),
        effects => extract(
            read([Dir, "include", "arizona_effect.hrl"]), ~"EFFECT_([A-Z0-9_]+),\\s*([0-9]+)"
        )
    }.

%% The ops the native backend can emit: the header minus the capability-gated ones.
native_backend_ops(#{ops := Ops}) ->
    maps:without([~"LIST_PATCH" || not arizona_json:supports_list_patch()], Ops).

json_client(Dir) ->
    extract(
        read([Dir, "e2e", "utils", "json_client.js"]), ~"EFFECT_([A-Z0-9_]+)\\s*=\\s*([0-9]+)"
    ).

%% The `const val NAME = N` entries inside the Kotlin `object Op { ... }` /
%% `object Effect { ... }`.
android(Kind) ->
    Wire = read([root(), "arizona", "src", "main", "kotlin", "dev", "arizona", "client", "Wire.kt"]),
    Body = block(Wire, [~"object ", block_name(Kind), ~" \\{(.*?)\\}"]),
    extract(Body, ~"([A-Z0-9_]+)\\s*=\\s*([0-9]+)").

block_name(ops) -> ~"Op";
block_name(effects) -> ~"Effect".

root() ->
    filename:dirname(filename:dirname(filename:absname(escript:script_name()))).

extract(Text, Pattern) ->
    case re:run(Text, Pattern, [global, {capture, all_but_first, binary}]) of
        {match, Rows} -> maps:from_list([{N, binary_to_integer(C)} || [N, C] <- Rows]);
        nomatch -> #{}
    end.

block(Text, Pattern) ->
    {match, [Body]} = re:run(Text, Pattern, [dotall, {capture, all_but_first, binary}]),
    Body.

read(Parts) ->
    {ok, Bin} = file:read_file(filename:join(Parts)),
    Bin.
