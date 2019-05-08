program clusters;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes,JwaWinIoctl,windows,sysutils
  { you can add units after this };

  function SetFilePointerEx (hFile: THandle; lDistanceToMove: int64; lpNewFilePointer: Pointer; dwMoveMethod: DWORD): BOOL; stdcall; external 'kernel32.dll';

procedure clusters(drive:ansistring);
var lpinbuf: ^STARTING_LCN_INPUT_BUFFER;
    hDevice: Cardinal;
    lpBytesReturned: PDWORD;
    j,value,k: byte;
    r: LongBool;
    FSCTL_GET_VOLUME_BITMAP: Cardinal;
    base: ^VOLUME_BITMAP_BUFFER;
    //
    bitmap_size,total_clusters,free_clusters:int64;
    //
    sVolumeData:NTFS_VOLUME_DATA_BUFFER;
    i,dwread,dwstart,dwend,dwtimer:dword;
    //
    //buffer:pointer;
    offset,extent:int64;
    ret:boolean;
    bytesread,byteswritten,clustersize:cardinal;
    cluster:integer;
    buf:array of byte;
    v:boolean;
begin

//  if messagebox(self.Handle ,pchar('zero all unused clusters for '+string(drive)+'?'),'CloneDisk',MB_YESNO)=id_no then  exit;


dwstart:=0;
dwend:=0;
v:=false;

  // Get a handle to our device
  hDevice := CreateFileA(PansiChar('\\.\'+drive),generic_read or generic_write,FILE_SHARE_READ or FILE_SHARE_WRITE,
                        nil,OPEN_EXISTING,0,0);
  // Check error
  if hDevice = INVALID_HANDLE_VALUE then
    begin
    writeln('INVALID_HANDLE_VALUE for '+ drive);
    exit;
    end;
// note that we could use GetDiskFreeSpace which will work for most file systems
//we only need the clustersize
if DeviceIoControl(hDevice,FSCTL_GET_NTFS_VOLUME_DATA,
                      nil,0,@sVolumeData,sizeof(sVolumeData),dwRead,nil) then
                      begin
                      clustersize:=sVolumeData.BytesPerCluster ;
                      //total:=(clustersize * int64(sVolumeData.TotalClusters.QuadPart)) div 1024 div 1024;
                      //free:=(clustersize * int64(sVolumeData.FreeClusters.QuadPart)) div 1024 div 1024;
                      total_clusters:= int64(sVolumeData.TotalClusters.QuadPart);
                      free_clusters:= int64(sVolumeData.FreeClusters.QuadPart);
                      end
                      else
                      begin
                      writeln('could not get ntfs data, not a NTFS volume?'+#13#10+inttostr(GetLastError));
                      //here we should check if we are facing a fat system
                      //if so we need to get the clustersize with getdiskfreespace and startinglcn with calculateFAToffset
                      closehandle(hDevice );
                      exit;
                      end;

  if v then
  begin
  writeln('total_clusters:'+inttostr(total_clusters));
  writeln('free_clusters:'+inttostr(free_clusters));
  writeln('used_clusters:'+inttostr(total_clusters-free_clusters));
  writeln('clustersize:'+inttostr(clustersize));
  writeln('****************************');
  end;

  //dwread:=0;
  //DeviceIoControl(hDevice,FSCTL_ALLOW_EXTENDED_DASD_IO,nil,0,nil,0,@dwread,nil);
  // Allocate memory and other initialization
  GetMem(base, sizeof(VOLUME_BITMAP_BUFFER)+1024*1024*64);
  GetMem(lpinbuf, sizeof(STARTING_LCN_INPUT_BUFFER));
  GetMem(lpBytesReturned, sizeof(DWORD));
  try
  lpinbuf^.StartingLcn.QuadPart := 0;
  FSCTL_GET_VOLUME_BITMAP := CTL_CODE(FILE_DEVICE_FILE_SYSTEM, 27, METHOD_NEITHER, FILE_ANY_ACCESS);
  // Make a query to device driver
  r := DeviceIOControl(hDevice, FSCTL_GET_VOLUME_BITMAP, lpinbuf, sizeof(STARTING_LCN_INPUT_BUFFER), base,
                  sizeof(VOLUME_BITMAP_BUFFER)+1024*1024*64, lpBytesReturned^, nil);
  //writeln('lpBytesReturned:'+inttostr(lpBytesReturned^));
  //writeln('StartingLcn:'+inttostr(base^.StartingLcn.QuadPart));
  //writeln('BitmapSize:'+inttostr(base^.BitmapSize.QuadPart));
  if (r) then
  begin
  //
  dwread:=0;
  bitmap_size:=base^.BitmapSize.QuadPart ;
  //
   dwread:=0;
   ret := DeviceIoControl(hdevice, FSCTL_LOCK_VOLUME, nil, 0, nil, 0, dwread, nil);
  {
  ret:=_DismountVolume(hdevice);
  if ret=false then
    begin
    writeln('dismount failed,'+inttostr(getlasterror));
    closehandle(hDevice );
    exit;
    end;
  }
  //
  SetFilePointer(hDevice, 0, nil, FILE_BEGIN);
  //
  //buffer := VirtualAlloc(nil,clustersize,MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
  setlength(buf,clustersize);for i:=0 to clustersize-1 do buf[i]:=0; //fillchar(buf,clustersize,0);
  //setlength(buf2,clustersize*8);for i:=0 to (clustersize*8)-1 do buf2[i]:=0; //fillchar(buf2,clustersize*8,0);
//
    cluster:=0;offset:=0;
    //pb_img.Max :=lpBytesReturned^;
    if v then writeln ('bitmap size: '+inttostr(lpBytesReturned^));
    dwstart:=gettickcount;
    dwtimer:=GetTickCount ;
    //
    extent:=0;
    //
for i := 0 to lpBytesReturned^ -1 do //we'll get one sector after the volume to list the backup sector
    begin
    value:= base^.Buffer[i];
    //if CancelFlag =true then break;
        if gettickcount-dwtimer>1000 then
        begin
          //pb_img.Position :=i;
          //Application.ProcessMessages ;
          dwtimer:=GetTickCount ;
        end;
        //we only go thru each bit if we have <> 00000000
        if value<>0 then
        begin
        //value=255
        //8 used clusters = 11111111 = 255 -> 8 all bits/clusters at once = 1 byte
        if value=255 then
        begin
          if v then writeln('used offset:'+inttostr(offset)+' size:'+inttostr(clustersize*8));
          if extent<>0 then
             begin
             writeln('extent:'+inttostr(extent)+' bytes at offset '+inttostr(offset-extent));
             extent:=0;
             end;
        inc(offset,clustersize*8 );
        end
        else
        //value<>255
        //mixed used and non used clusters -> we need to go thru each single bits
        begin
        for j := 0 to 7 do
        begin
        //The bitmap uses one bit to represent each cluster
        //Array of bytes containing the bitmap that the operation returns.
        //The bitmap is bitwise from bit zero of the bitmap to the end.
        //Thus, starting at the requested cluster, the bitmap goes from bit 0 of byte 0, bit 1 of byte 0 ... bit 7 of byte 0, bit 0 of byte 1, and so on.
        //The value 1 indicates that the cluster is allocated (in use). The value 0 indicates that the cluster is not allocated (free).
        //odd(value shr j)->1
          if odd(value shr j)
            then
            begin
              if v then writeln('used offset:'+inttostr(offset)+' size:'+inttostr(clustersize));
              if extent<>0 then
              begin
              writeln('extent:'+inttostr(extent)+' bytes at offset '+inttostr(offset-extent));
              extent:=0;
              end;
            end//if odd(value shr j)
            else
            begin
            if v then writeln('unused offset:'+inttostr(offset)+' size:'+inttostr(clustersize));
            inc(extent,clustersize );
            if SetFilePointerEx(hdevice,offset,nil,file_begin)=true then
              begin
              {//we dont want to zero!!!!
              ret:=windows.WriteFile(hDevice ,buf[0],clustersize ,byteswritten,nil );
              if ret=false then raise exception.Create ('writefile failed,'+inttostr(getlasterror));
              inc(cluster);
              }
              end;
            end;
        inc(offset,clustersize );
        end; //for j := 0 to 7 do
        end; //if base^.Buffer[i]=255 then else

        end //if base^.Buffer[i]<>0 then
        else
        begin
        //value=0 -> 8 unused clusters;
        if v then writeln('unused offset:'+inttostr(offset)+' size:'+inttostr(clustersize*8));
        inc(extent,clustersize*8 );
        if SetFilePointerEx(hdevice,offset,nil,file_begin)=true then
          begin
          for k:=0 to 7 do
            begin
            {//we dont want to zero!!!!
            ret:=windows.WriteFile(hDevice ,buf[0],clustersize ,byteswritten,nil );
            if ret=false then raise exception.create('writefile failed,'+inttostr(getlasterror));
            inc(cluster);
            }
            end;
          end;
        inc (offset,clustersize*8);
        end;
    end;//for i := 0 to lpBytesReturned^ do
  dwend:=gettickcount;
  //pb_img.Position:=pb_img.max;
  //
  //VirtualFree(buffer,clustersize, MEM_RELEASE);
  //
  end;//if (r) then
  except
  on e:exception do writeln(e.message);
  end;
  // Free memory and other finalization
  dwread := 0;
  ret:=DeviceIoControl(hdevice,FSCTL_UNLOCK_VOLUME,nil,0,nil,0,dwread,nil);
  CloseHandle(hDevice);
  FreeMem(base, sizeof(VOLUME_BITMAP_BUFFER)+1024*1024*64);
  FreeMem(lpinbuf, sizeof(STARTING_LCN_INPUT_BUFFER));
  FreeMem(lpBytesReturned, sizeof(DWORD));
  //
  //StatusBar1.SimpleText := 'zeroed clusters : '+inttostr(cluster)+' ('+inttostr(cluster*clustersize div 1024 div 1024)+'MB) in '+inttostr((dwend-dwstart) div 1000)+' secs.';
end;

begin
if Paramcount=0 then
  begin
  writeln('clusters drive');
  exit;
  end;
clusters (paramstr(1));
end.

