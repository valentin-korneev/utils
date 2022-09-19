prompt create or replace package body Util_IP

create or replace package body Util_IP
as

BASE      constant int := 36;
TMIN      constant int :=  1;
TMAX      constant int := 26;
MAXINT    constant int := 2147483647; -- 0x7fffffff

---------
function ValidateIp(aIpAddress int, aNetwork int, aNetmask int) return boolean
is
begin
  return case
          when aNetmask is null then aIpAddress = aNetwork
          else bitand(aIpAddress, aNetmask) = aNetwork
         end;
end ValidateIp;

---------
function IntToStr(aIpAddress int) return varchar2
is
  fRes varchar2(18);
  --
  fDec int;
begin
  for i in reverse 1 .. 4 loop
    fDec := trunc(mod(aIpAddress, 256**i) / 256**(i-1));
    Util.CheckErr(not fDec between 0 and 255, '%d - не €вл€етс€ IP-адресом', aIpAddress);
    fRes := fRes || fDec || '.';
  end loop;

  return rtrim(fRes, '.');
end IntToStr;

---------
function StrToInt(aIpAddress varchar2) return int
is
  fMatched boolean := false;
  fParseRes owa_text.vc_arr;
  --
  fRes int := 0;
begin
  fMatched := owa_pattern.match(aIpAddress, '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$', fParseRes);

  Util.CheckErr(not fMatched, 'Ќеверный формат IP-адреса "%s"', aIpAddress);

  for i in 1 .. 4 loop
    Util.CheckErr(not fParseRes(i) between 0 and 255, 'Ќеверный формат IP-адреса "%s"', aIpAddress);
    fRes := fRes + fParseRes(i)*power(256, 4-i);
  end loop;

  return fRes;
end StrToInt;


---------
function IsValidIpAddress(aIpAddress varchar2) return boolean
is
begin
  return regexp_like(aIpAddress || '.', '^(([01]?\d\d?|2[0-4]\d|25[0-5])\.){4}$');
end IsValidIpAddress;


---------
procedure CheckIpAddress(aIpAddress varchar2)
is
begin
  Util.CheckErr(not IsValidIpAddress(aIpAddress), 'Ќеверный IP-адрес: %s', aIpAddress);
end CheckIpAddress;


---------
procedure ParseNetwork(aNetwork varchar2, aIpAddress out int, aNetmask out int)
is
  fMatched boolean := false;
  fRes owa_text.vc_arr;
begin
  fMatched := owa_pattern.match(aNetwork, '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$', fRes);

  if fMatched then
    aIpAddress := StrToInt(fRes(1));
  else
    fMatched := owa_pattern.match(aNetwork, '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$', fRes);
    Util.CheckErr(not fMatched, 'Ќеверный формат сети "%s"', aNetwork);

    aIpAddress := StrToInt(fRes(1));

    if fRes.exists(2) then
      Util.CheckErr(not fRes(2) between 0 and 32, 'Ќеверный формат маски подсети "%s"', aNetwork);
      if fRes(2) <> 32 then
        aNetmask := (2**32 - 1) - (2**(32 - fRes(2)) - 1);
      end if;
    end if;

    if aNetmask is not null then
      Util.CheckErr(bitand(aNetmask, aIpAddress) <> aIpAddress, '«аданный IP-адрес не согласуетс€ с маской подсети');
    end if;
  end if;
end ParseNetwork;

---------
function GetLocationId(aIpAddress varchar2) return number
is
  fIpAddress int := 0;
  fDistance int := 256;
begin
  checkIpAddress(aIpAddress);
  fIpAddress := StrToInt(aIpAddress);
  for i in 0..3 loop
    for cItem in 
    (
      select /*+ index(util_ip_range util_ip_range$pk$net$first$l)*/
        location_id as location
        from util_ip_range 
        where network_class = i
          and first_ip_int between fIpAddress - (fDistance-1) and fIpAddress
          and last_ip_int >= fIpAddress
        order by last_ip_int-first_ip_int
    ) loop
      return cItem.location;
    end loop;
    fDistance := fDistance * 256;
  end loop;
  return null;
end GetLocationId;

---------
function GetCountry(aIpAddress varchar2) return varchar2
is
  country util_ip_location.country%type;
  city util_ip_location.city%type;
begin
  GetCountryAndCity(aIpAddress, country, city);
  return country;
end GetCountry;

---------
function GetCity(aIpAddress varchar2) return varchar2
is
  country util_ip_location.country%type;
  city util_ip_location.city%type;
begin
  GetCountryAndCity(aIpAddress, country, city);
  return city;
end GetCity;

---------
procedure GetCountryAndCity(aIpAddress varchar2, aCountry out varchar2, aCity out varchar2)
is
  locationId int := GetLocationId(aIpAddress);
begin
  for cItem in 
  (
    select city, country  
      from util_ip_location
      where id = locationId
  ) loop
    aCountry := cItem.country;
    aCity := cItem.city;
  end loop;
end GetCountryAndCity;

---------
function GetOwaIpAddress(aOnlyFirst boolean := false) return varchar2
is
  fIp varchar2(2000);
begin
  if owa.num_cgi_vars is not null then 
    fIp := coalesce
           ( owa_util.get_cgi_env('X-Client-Address')
           , owa_util.get_cgi_env('x-Forwarded-for')
           , owa_util.get_cgi_env('REMOTE_ADDR')
           );
    if aOnlyFirst then
      fIp := regexp_substr(fIp, '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}');
    end if;
  end if;
  return fIp;
end GetOwaIpAddress;

---------
function DecodeDigit(aCP int) return int
is
begin
  if aCP - 48 < 10 then
    return aCP - 22;
  elsif aCP - 65 < 26 then
    return aCP - 65;
  elsif (aCP - 97 < 26) then
    return aCP - 97;
  else
    return BASE;
  end if;
end DecodeDigit;

--

function GetToken(aStr varchar2, aInd number) return varchar2
is
  fHead int;
  fTail int;
begin
  if aInd = 1 then
    fHead := 1;
  else
    fHead := instr(aStr, '.', 1, aInd - 1);
    if fHead = 0 then
      return null;
    else
      fHead := fHead + 1;
    end if;
  end if;
  fTail := instr(aStr, '.', fHead, 1);
  if fTail = 0 then
    return substr(aStr, fHead);
  else
    return substr(aStr, fHead, fTail - fHead);
  end if;
end GetToken;

--

function UnicodeString(aN int) return varchar2
is
begin
  if aN is null then
    return null;
  end if;
  if aN < 65536 then
    return unistr('\' || lpad(to_char(aN, 'FMXXXX'), 4, '0'));
  end if;
  return unistr('\' || lpad(to_char(trunc((aN - 65536) / 1024) + 55296, 'FMXXXX'), 4, '0')
             || '\' || lpad(to_char(   mod(aN - 65536,   1024) + 56320, 'FMXXXX'), 4, '0')
               );
end UnicodeString;

--

function EncodeDigit(aN int) return int
is
begin
  --dbms_output.put_line(aN || ' -> ' || (aN + 22 + 75 * (case when aN < 26 then 1 else 0 end)));
  return aN + 22 + 75 * (case when aN < 26 then 1 else 0 end);
end EncodeDigit;

--

function Adapt(aInputDelta int, aNumPoints int, aFirstTime boolean) return int
is
  i      int := 0;
  fDelta number;
begin
  fDelta := trunc(aInputDelta / case when aFirstTime then 700 else 2 end);
  fDelta := fDelta + trunc(fDelta / aNumPoints);
  loop
    exit when fDelta <= ((BASE - TMIN) * TMAX) / 2;
    fDelta := trunc(fDelta / (BASE - TMIN));
    i := i + BASE;
  end loop;
  return trunc(i + (BASE - TMIN + 1) * fDelta / (fDelta + 38));
end Adapt;

--

function DecodePunycode(aInput varchar2) return varchar2
is
  type TStringArray is varray(255) of varchar2(5); -- length('\HHHH')
  fOutputArr TStringArray := TStringArray();
  fBasic  int := instrc(aInput, '-', -1, 1) - 1;
  fBias   int := 72;
  fNewI   int := 0;
  n       int := 128;
  o       int := 0;
  ic      int := 0;
  fDigit  int;
  fOldI   int;
  w       int;
  k       int;
  t       int;
  fOutput varchar2(256);
begin
  if fBasic < 0 then
    fBasic := 0;
  end if;
  for j in 1..fBasic loop
    if ascii(substr(aInput, j, 1)) >= 128 then
      return null;
    end if;
    fOutputArr.extend;
    fOutputArr(j) := substr(aInput, j, 1);
    o := o + 1;
  end loop;
  if fBasic > 0 then
    ic := fBasic + 1;
  end if;
  while ic < nvl(length(aInput), 0) loop
    fOldI := fNewI;
    w := 1;
    k := base;
    loop
      if ic >= nvl(length(aInput), 0) then
        return null;
      end if;
      ic := ic + 1;
      fDigit := DecodeDigit(ascii(substrc(aInput, ic, 1)));
      if fDigit >= BASE then
        return null;
      end if;
      if fDigit > trunc((MAXINT - fNewI) / w) then
        return null;
      end if;
      fNewI := fNewI + fDigit * w;
      t := case
             when k <= fBias        then TMIN
             when k >= fBias + TMAX then TMAX
                                    else k - fBias
           end;
      exit when fDigit < t;
      if w > trunc(MAXINT / (BASE - t)) then
        return null;
      end if;
      w := w * (BASE - t);
      k := k + BASE;
    end loop;
    o := o + 1;
    fBias := Adapt(fNewI - fOldI, o, fOldI = 0);
    if trunc(fNewI / o) > MAXINT - n then
      return null;
    end if;
    n := n + trunc(fNewI / o);
    fNewI := mod(fNewI, o);
    fOutputArr.extend;
    for j in 1..fOutputArr.count - fNewI loop
      exit when fOutputArr.count - j < 1;
      fOutputArr(fOutputArr.count - j + 1) := fOutputArr(fOutputArr.count - j);
    end loop;
    fOutputArr(fNewI + 1) := UnicodeString(n);
    fNewI := fNewI + 1;
  end loop;
  for j in 1..fOutputArr.count loop
    fOutput := fOutput || fOutputArr(j);
  end loop;
  return fOutput;
end DecodePunycode;
    
--

function EncodePunycode(aInput varchar2) return varchar2
is
  n       int := 128;
  fDelta  int := 0;
  fBias   int := 72;
  h       int;
  b       int;
  j       int;
  m       int;
  q       int;
  k       int;
  t       int;
  ijv     int;
  fOutput varchar2(256);
  fInput  varchar2(2000);
begin
  fInput := utl_i18n.string_to_raw(aInput, 'AL16UTF16');
  for j in 1..nvl(length(aInput), 0) loop
    if to_number(substr(fInput, (j - 1) * 4 + 1, 4), 'XXXX') < 128 then
      fOutput := fOutput || substr(aInput, j, 1);
    end if;
  end loop;
  b := nvl(length(fOutput), 0);
  h := b;
  if b > 0 then
    fOutput := fOutput || '-';
  end if;
  while h < nvl(length(aInput), 0) loop
    m := MAXINT;
    for j in 1..nvl(length(aInput), 0) loop
      ijv := to_number(substr(fInput, (j - 1) * 4 + 1, 4), 'XXXX');
      if ijv >= n and ijv < m then
        m := ijv;
      end if;
    end loop;
    if m - n > trunc((MAXINT - fDelta) / (h + 1)) then
      return null;
    end if;
    fDelta := fDelta + (m - n) * (h + 1);
    n := m;
    for j in 1..nvl(length(aInput), 0) loop
      ijv := to_number(substr(fInput, (j - 1) * 4 + 1, 4), 'XXXX');
      if ijv < n then
        fDelta := fDelta + 1;
        if fDelta > MAXINT then
          return null;
        end if;
      end if;
      if ijv = n then
        q := fDelta;
        k := BASE;
        loop
          t := case
                 when k <= fBias        then TMIN
                 when k >= fBias + TMAX then TMAX
                                        else k - fBias
               end;
          exit when q < t;
          fOutput := fOutput || chr(EncodeDigit(t + mod(q - t, BASE - t)));
          q := trunc((q - t) / (BASE - t));
          k := k + BASE;
        end loop;
        fOutput := fOutput || chr(EncodeDigit(q));
        fBias := Adapt(fDelta, h + 1, h = b);
        fDelta := 0;
        h := h + 1;
      end if;
    end loop;
    fDelta := fDelta + 1;
    n := n + 1;
  end loop;
  return fOutput;
end EncodePunycode;

----------

function Ascii2Domain(aDomain varchar2) return varchar2
is
  fDots   int := nvl(length(aDomain), 0) - nvl(length(replace(aDomain, '.')), 0);
  fResult varchar2(256);
  fPart   varchar2(256);
begin
  for i in 0..fDots loop
    fPart := GetToken(aDomain, i + 1);
    if substr(fPart, 1, 4) = 'xn--' then
      fPart := DecodePunycode(substrc(fPart, 5));
    end if;
    fResult := fResult || fPart;
    if i <> fDots then
      fResult := fResult || '.';
    end if;
  end loop;
  return fResult;
end Ascii2Domain;

--

function Domain2Ascii(aDomain varchar2) return varchar2
is
  fDots   int := nvl(length(aDomain), 0) - nvl(length(replace(aDomain, '.')), 0);
  fResult varchar2(256);
  fPart   varchar2(256);
begin
  for i in 0..fDots loop
    fPart := GetToken(lower(aDomain), i + 1);
    if fPart <> asciistr(to_char(fPart)) then
      fPart := 'xn--' || EncodePunycode(fPart);
    end if;
    fResult := fResult || fPart;
    if i <> fDots then
      fResult := fResult || '.';
    end if;
  end loop;
  return fResult;
end Domain2Ascii;





---------
procedure ParseHostAndPort(aHostAndPort varchar2, aHost out varchar2, aPort out int, aDefaultPort int := null)
is
  cRE_HostAndPort constant varchar2(99) := '^([^:@]{1,255})(:(\d{2,5}))?$';
begin
  Util.CheckErr(aHostAndPort is null or not regexp_like(aHostAndPort, cRE_HostAndPort), '%s - неверный формат дл€ хост[:порт]', aHostAndPort);
  aHost :=     regexp_substr(aHostAndPort, cRE_HostAndPort, 1, 1, '', 1);
  aPort := nvl(regexp_substr(aHostAndPort, cRE_HostAndPort, 1, 1, '', 3), aDefaultPort);
  Util.CheckErr(aPort is null, '%s - не указан порт', aHostAndPort);
end ParseHostAndPort;

---------
procedure ValidateHostAndPort(aHostAndPort varchar2, aDefaultPort int := null)
is
  fHost varchar2(255);
  fPort int;
begin
  ParseHostAndPort(aHostAndPort, fHost, fPort, aDefaultPort);
end ValidateHostAndPort;

---------
function IsValidHostAndPort(aHostAndPort varchar2, aDefaultPort int := null) return boolean
is
begin
  ValidateHostAndPort(aHostAndPort, aDefaultPort);
  return true;
exception
  when Util.eStandardException then
    return false;
end IsValidHostAndPort;

---------
end Util_IP;
/
show err
