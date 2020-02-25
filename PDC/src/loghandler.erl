%% @author BlackBase
%% @doc @todo Add description to loghandler.


-module(loghandler).

-export([init/3,handler/5]).

-include("types.hrl").

%% ConfigTuple Has Some Element For Managing %%

init({FileNameDataOut,FileNameLogOut,IsDataCapture,IsLogCapture},FL,PPid)->
	% Initilize Pre Started %
	io:fwrite("##LogHandler Process##"),
	
	FDLO=case file:open(FileNameLogOut++"/wroute.log", [append,read,binary]) of
		{ok,IoDeviceL}->
			IoDeviceL;
		{error,Reason}->
			exit(Reason)
	end,
	
	FDDOList=init_file(FL,FileNameDataOut,[]),

	
	handler(FDLO,FDDOList,IsDataCapture,IsLogCapture,PPid).

init_file([],FileNameDataOut,ListFDDO)->ListFDDO;
init_file([H|T],FileNameDataOut,ListFDDO)->
	FDDO=case file:open(FileNameDataOut++"/wroute_"++integer_to_list(H#peer.p1port)++"_"++H#peer.p2++".data", [append,read,binary]) of
		{ok,IoDeviceD}->
			IoDeviceD;
		{error,Reason}->
			exit(Reason)
	end,
	
	DList=length(H#peer.duplicates),
	if DList > 0->
		DInnerList=init_file(H#peer.duplicates,FileNameDataOut,[]);
	true->
		DInnerList=[]
	end,
	
	init_file(T,FileNameDataOut,ListFDDO++[{H#peer.p1port,H#peer.p2,FDDO}]++DInnerList).

handler(FDLO,FDDOList,IsDataCapture,IsLogCapture,PPid)->
	receive
		{log,StaticMsg,DynamicMsg,stdout}->
			
			if IsLogCapture == 1 ->
				   io:fwrite(StaticMsg++"~w~n",[DynamicMsg]);
			   IsLogCapture == 2 ->
				   self() ! {log,StaticMsg,DynamicMsg,file};
			   IsLogCapture == 3 ->
				   io:fwrite(StaticMsg++"~w~n",[DynamicMsg]),
			   	   self() ! {log,StaticMsg,DynamicMsg,file};
			   true ->
				   handler(FDLO,FDDOList,IsDataCapture,IsLogCapture,PPid)
			end,
			
			handler(FDLO,FDDOList,IsDataCapture,IsLogCapture,PPid);
		
		{log,StaticMsg,DynamicMsg,file}->

			if (IsLogCapture == 2) or (IsLogCapture == 3) ->
				   file:write(FDLO, StaticMsg),
			   	   file:write(FDLO, io_lib:format("~p~n", [DynamicMsg])),
				   handler(FDLO,FDDOList,IsDataCapture,IsLogCapture,PPid);
			true->
				handler(FDLO,FDDOList,IsDataCapture,IsLogCapture,PPid)
			end;
		
		{data,Data,file,CaptureList}->
			
			if IsDataCapture == 1 ->
				write_CaptureList(CaptureList,FDDOList,Data),
				   
				handler(FDLO,FDDOList,IsDataCapture,IsLogCapture,PPid);
			true->
				handler(FDLO,FDDOList,IsDataCapture,IsLogCapture,PPid)
			end;
		
		{close}->
		  	file:close(FDLO),
			close_FDDList(FDDOList),
			
			handler(FDLO,FDDOList,IsDataCapture,IsLogCapture,PPid)
	end.

write_CaptureList([],FDDOList,Data)-> ok;
write_CaptureList([H|T],FDDOList,Data)->
	FDDO=find_DRitem(FDDOList, H),
	if FDDO /= false->
		file:write(FDDO, Data),
		file:write(FDDO,<<"~#~SECTION~#~">>),
						
		write_CaptureList(T,FDDOList,Data);	  
	true->
		write_CaptureList(T,FDDOList,Data)
	end.

find_DRitem([],DR)->false;
find_DRitem([H|T],DR)->
	{DRPort,DRIP,FDDO}=H,
	if (DRPort == DR#peer.p1port) and (DRIP == DR#peer.p2) ->
		FDDO;
	true->
		find_DRitem(T,DR)
	end.

close_FDDList([])->true;
close_FDDList([H|T])->
	{DRPort,FDDO}=H,
	file:close(FDDO),
	close_FDDList(T).

log_register(Struct)->
	Pid=erlang:whereis(wrouteL),
	Pid ! Struct.
