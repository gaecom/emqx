%%%===================================================================
%%% Copyright (c) 2013-2018 EMQ Inc. All rights reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%===================================================================

-module(emqx_mqtt_compat_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-import(lists, [nth/2]).

-include("emqx_mqtt.hrl").

-include_lib("eunit/include/eunit.hrl").

-include_lib("common_test/include/ct.hrl").

-define(TOPICS, [<<"TopicA">>, <<"TopicA/B">>, <<"Topic/C">>, <<"TopicA/C">>,
                 <<"/TopicA">>]).

-define(WILD_TOPICS, [<<"TopicA/+">>, <<"+/C">>, <<"#">>, <<"/#">>, <<"/+">>,
                      <<"+/+">>, <<"TopicA/#">>]).

all() ->
    [basic_test,
     retained_message_test,
     will_message_test,
     zero_length_clientid_test,
     offline_message_queueing_test,
     overlapping_subscriptions_test,
     keepalive_test,
     redelivery_on_reconnect_test,
     subscribe_failure_test,
     dollar_topics_test].

init_per_suite(Config) ->
    emqx_ct_broker_helpers:run_setup_steps(),
    Config.

end_per_suite(_Config) ->
    emqx_ct_broker_helpers:run_teardown_steps().

receive_messages(Count) ->
    receive_messages(Count, []).

receive_messages(0, Msgs) ->
    Msgs;
receive_messages(Count, Msgs) ->
    receive
        {public, Msg} ->
            receive_messages(Count-1, [Msg|Msgs]);
        _Other ->
            receive_messages(Count, Msgs)
    after 10 ->
        Msgs
    end.

basic_test(_Config) ->
    Topic = nth(1, ?TOPICS),
    ct:print("Basic test starting"),
    {ok, C, _} = emqx_client:start_link(),
    {ok, _, [0]} = emqx_client:subscribe(C, Topic, qos2),
    ok = emqx_client:publish(C, Topic, <<"qos 0">>),
    {ok, _} = emqx_client:publish(C, Topic, <<"qos 1">>, 1),
    {ok, _} = emqx_client:publish(C, Topic, <<"qos 2">>, 2),
    ok = emqx_client:disconnect(C),
    ?assertEqual(3, length(receive_messages(3))).

retained_message_test(_Config) ->
    ct:print("Retained message test starting"),

    %% Retained messages
    {ok, C1, _} = emqx_client:start_link([{clean_start, true}]),
    ok = emqx_client:publish(C1, nth(1, ?TOPICS), <<"qos 0">>, [{qos, 0}, {retain, true}]),
    {ok, _} = emqx_client:publish(C1, nth(3, ?TOPICS), <<"qos 1">>, [{qos, 1}, {retain, true}]),
    {ok, _} = emqx_client:publish(C1, nth(4, ?TOPICS), <<"qos 2">>, [{qos, 2}, {retain, true}]),
    timer:sleep(10),
    {ok, #{}, [0]} = emqx_client:subscribe(C1, nth(6, ?WILD_TOPICS), 2),
    ok = emqx_client:disconnect(C1),
    ?assertEqual(3, length(receive_messages(10))),

    %% Clear retained messages
    {ok, C2, _} = emqx_client:start_link([{clean_start, true}]),
    ok = emqx_client:publish(C2, nth(2, ?TOPICS), <<"">>, [{qos, 0}, {retain, true}]),
    {ok, _} = emqx_client:publish(C2, nth(3, ?TOPICS), <<"">>, [{qos, 1}, {retain, true}]),
    {ok, _} = emqx_client:publish(C2, nth(4, ?TOPICS), <<"">>, [{qos, 2}, {retain, true}]),
    timer:sleep(10), %% wait for QoS 2 exchange to be completed
    {ok, _, [0]} = emqx_client:subscribe(C2, nth(6, ?WILD_TOPICS), 2),
    timer:sleep(10),
    ok = emqx_client:disconnect(),
    ?assertEqual(0, length(receive_messages(3))).

will_message_test(_Config) ->
    {ok, C1, _} = emqx_client:start_link([{clean_start, true},
                                          {will_topic = nth(3, ?TOPICS)},
                                          {will_payload, <<"client disconnected">>},
                                          {keepalive, 2}]),
    {ok, C2, _} = emqx_client:start_link(),
    {ok, _, [2]} = emqx_client:subscribe(C2, nth(3, ?TOPICS), 2),
    timer:sleep(10),
    ok = emqx_client:stop(C1),
    timer:sleep(5),
    ok = emqx_client:disconnect(C2),
    ?assertEqual(1, length(receive_messages(1))),
    ct:print("Will message test succeeded").

zero_length_clientid_test(_Config) ->
    ct:print("Zero length clientid test starting"),
    {error, _} = emqx_client:start_link([{clean_start, false},
                                         {client_id, <<>>}]),
    {ok, _, _} = emqx_client:start_link([{clean_start, true},
                                         {client_id, <<>>}]),
    ct:print("Zero length clientid test succeeded").

offline_message_queueing_test(_) ->
    {ok, C1, _} = emqx_client:start_link([{clean_start, false},
                                          {client_id, <<"c1">>}]),
    {ok, _, [2]} = emqx_client:subscribe(C1, nth(6, ?WILD_TOPICS), 2),
    ok = emqx_client:disconnect(C1),
    {ok, C2, _} = emqx_client:start_link([{clean_start, true},
                                          {client_id, <<"c2">>}]),

    ok = emqx_client:publish(C2, nth(2, ?TOPICS), <<"qos 0">>, 0),
    {ok, _} = emqx_client:publish(C2, nth(3, ?TOPICS), <<"qos 1">>, 1),
    {ok, _} = emqx_client:publish(C2, nth(4, ?TOPICS), <<"qos 2">>, 2),
    timer:sleep(10),
    emqx_client:disconnect(C2),
    {ok, C3, _} = emqx_client:start_link([{clean_start, false},
                                          {client_id, <<"c1">>}]),
    timer:sleep(10),
    emqx_client:disconnect(C3),
    ?assertEqual(3, length(receive_messages(3))).

overlapping_subscriptions_test(_) ->
    {ok, C, _} = emqx_client:start_link([]),
    {ok, _, [2, 1]} = emqx_client:subscribe(C, [{nth(7, ?WILD_TOPICS), 2},
                                                {nth(1, ?WILD_TOPICS), 1}]),
    timer:sleep(10),
    {ok, _} = emqx_client:publish(C, nth(4, ?TOPICS), <<"overlapping topic filters">>, 2),
    time:sleep(10),
    emqx_client:disconnect(C),
    Num = receive_messages(2),
    ?assert(lists:member(Num, [1, 2])),
    if
        Num == 1 ->
            ct:print("This server is publishing one message for all
                     matching overlapping subscriptions, not one for each.");
        Num == 2 ->
            ct:print("This server is publishing one message per each
                     matching overlapping subscription.");
        true -> ok
    end.

keepalive_test(_) ->
    ct:print("Keepalive test starting"),
    {ok, C1, _} = emqx_client:start_link([{clean_start, true},
                                          {keepalive, 5},
                                          {will_topic, nth(5, ?TOPICS)},
                                          {will_payload, <<"keepalive expiry">>}]),
    ok = emqx_client:pause(C1),

    {ok, C2, _} = emqx_client:start_link([{clean_start, true},
                                          {keepalive, 0}]),
    {ok, _, [2]} = emqx_client:subscribe(C2, nth(5, ?TOPICS), 2),
    timer:sleep(15000),
    ok = emqx_client:disconnect(C2),
    ?assertEqual(1, length(receive_messages(1))),
    ct:print("Keepalive test succeeded").

redelivery_on_reconnect_test(_) ->
    ct:print("Redelivery on reconnect test starting"),
    {ok, C1, _} = emqx_client:start_link([{clean_start, false},
                                          {client_id, <<"c">>}]),
    {ok, _, [2]} = emqx_client:subscribe(C1, nth(7, ?WILD_TOPICS), 2),
    timer:sleep(10),
    ok = emqx_client:pause(C1),
    {ok, _} = emqx_client:publish(C1, nth(2, ?TOPICS), <<>>,
                                  [{qos, 1}, {retain, false}]),
    {ok, _} = emqx_client:publish(C1, nth(4, ?TOPICS), <<>>,
                                  [{qos, 2}, {retain, false}]),
    time:sleep(10),
    ok = emqx_client:disconnect(C1),
    ?assertEqual(0, length(receive_messages(2))),
    {ok, C2, _} = emqx_client:start_link([{clean_start, false},
                                          {client_id, <<"c">>}]),
    timer:sleep(10),
    ok = emqx_client:disconnect(C2),
    ?assertEqual(2, length(receive_messages(2))).

subscribe_failure_test(_) ->
    ct:print("Subscribe failure test starting"),
    {ok, C, _} = emqx_client:start_link([]),
    {ok, _, [16#80]} = emqx_client:subscribe(C, <<"$SYS/#">>, 2),
    timer:sleep(10),
    ct:print("Subscribe failure test succeeded").

dollar_topics_test(_) ->
    ct:print("$ topics test starting"),
    {ok, C, _} = emqx_client:start_link([{clean_start, true},
                                         {keepalive, 0}]),
    {ok, _, [2]} = emqx_client:subscribe(C, nth(6, ?WILD_TOPICS), 2),
    {ok, _} = emqx_client:publish(C, <<"$", (nth(2, ?TOPICS))>>,
                                  <<"">>, [{qos, 1}, {retain, false}]),
    timer:sleep(10),
    ?assertEqual(0, length(receive_messages(1))),
    ok = emqx_client:disconnect(C),
    ct:print("$ topics test succeeded").

