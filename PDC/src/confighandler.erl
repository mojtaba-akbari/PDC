%% @author BlackBase
%% @doc @todo Add description to confighandler.


-module(confighandler).

-export([init/1]).

-include("types.hrl").


file_lines(File,Lines)->
  case file:read_line(File) of
		{ok,Line}->
			
			NewLine=lists:delete($\n, Line),
			Len=string:len(NewLine),
			CommentLine=string:chr(NewLine,$#),
			
			if (CommentLine /= 1) and (Len > 0) ->
				file_lines(File,Lines++[NewLine]);
			true ->
		   		file_lines(File,Lines)
			end;
	  
		eof->
			Lines
  end.

filter_lines([],DRList,Cfg=#config{})-> {DRList,Cfg};
filter_lines([H|T],DRList,Cfg=#config{})->

	case string:split(H, "=") of
		["listen",Data]->
			[P1,IP,P2,MASTER,DUP,REPLICA]=string:tokens(Data, ":"),
			DR=#peer{p1="any",p1port=list_to_integer(P1),p2=IP,p2port=list_to_integer(P2),master=list_to_integer(MASTER),last=1,alive=1,replica=list_to_integer(REPLICA),duplicates=[]},
			
			filter_lines(T,DRList++[DR],Cfg);
		
		["duplicate",Data]->
			[P1,IP,P2,MASTER,DUP,REPLICA]=string:tokens(Data, ":"),
			
			% Get Duplicate Item Add to Master Item And Rewrite DRList %
			DP=#peer{p1="any",p1port=list_to_integer(P1),p2=IP,p2port=list_to_integer(P2),master=list_to_integer(MASTER),last=0,alive=1,replica=list_to_integer(REPLICA),duplicates=[]},
			DRO=lists:nth(list_to_integer(DUP),DRList),
			
			DR=#peer{p1=DRO#peer.p1,p1port=DRO#peer.p1port,p2=DRO#peer.p2,p2port=DRO#peer.p2port,master=DRO#peer.master,last=DRO#peer.last,alive=DRO#peer.alive,replica=DRO#peer.replica,duplicates=DRO#peer.duplicates++[DP]},
			DRListTMP=lists:delete(DRO, DRList),
			
			{Left, Right} = lists:split(list_to_integer(DUP)-1, DRListTMP),

			filter_lines(T,Left ++ [DR|Right],Cfg);
		
		["logging",Data]->
			CfgTMP=#config{logging=list_to_integer(Data),logfile=Cfg#config.logfile,capture=Cfg#config.capture,capturefile=Cfg#config.capturefile,recovery=Cfg#config.recovery,ha=Cfg#config.ha},
			filter_lines(T,DRList,CfgTMP);
		
		["logfile",Data]->
			CfgTMP=#config{logging=Cfg#config.logging,logfile=Data,capture=Cfg#config.capture,capturefile=Cfg#config.capturefile,recovery=Cfg#config.recovery,ha=Cfg#config.ha},
			filter_lines(T,DRList,CfgTMP);
		
		["capture",Data]->
			CfgTMP=#config{logging=Cfg#config.logging,logfile=Cfg#config.logfile,capture=list_to_integer(Data),capturefile=Cfg#config.capturefile,recovery=Cfg#config.recovery,ha=Cfg#config.ha},
			filter_lines(T,DRList,CfgTMP);
		
		["capturefile",Data]->
			CfgTMP=#config{logging=Cfg#config.logging,logfile=Cfg#config.logfile,capture=Cfg#config.capture,capturefile=Data,recovery=Cfg#config.recovery,ha=Cfg#config.ha},
			filter_lines(T,DRList,CfgTMP);
		
		["recovery",Data]->
			CfgTMP=#config{logging=Cfg#config.logging,logfile=Cfg#config.logfile,capture=Cfg#config.capture,capturefile=Cfg#config.capturefile,recovery=list_to_integer(Data),ha=Cfg#config.ha},
			filter_lines(T,DRList,CfgTMP);
		
		["ha",Data]->
			CfgTMP=#config{logging=Cfg#config.logging,logfile=Cfg#config.logfile,capture=Cfg#config.capture,capturefile=Cfg#config.capturefile,recovery=Cfg#config.recovery,ha=list_to_integer(Data)},
			filter_lines(T,DRList,CfgTMP);
		
		_->
			filter_lines(T,DRList,Cfg)
	end.
		
init(ConfigFile)->
	{ok,CF}=file:open(ConfigFile,[read]),
	Lines=file_lines(CF,[]),
	Cfg=#config{},
	{PairList,Conf}=filter_lines(Lines,[],Cfg),
	{PairList,Conf}.
	
