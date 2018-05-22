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

-module(emqx_sys_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Sys = {sys, {emqx_sys, start_link, []},
           permanent, 5000, worker, [emqx_sys]},

    {ok, Env} = emqx_config:get_env(sysmon),
    Sysmon = {sys_mon, {emqx_sys_mon, start_link, [Env]},
              permanent, 5000, worker, [emqx_sys_mon]},
    {ok, {{one_for_one, 10, 100}, [Sys, Sysmon]}}.

