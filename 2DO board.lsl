// 2DO board
//
// In-word teleporter board for 2DO events server.
//
// * Get the latest version in-world at Speculoos Lab:
//      hop://speculoos.world:8002/Lab
// * or from git repository
//      https://git.magiiic.com/opensimulator/2do-board
//
// Licence: GPLv3
// © 2018-2019 Gudule Lapointe <gudule@speculoos.world>
//   Initial project author: Tom Frost <tomfrost@linkwater.org>

////////////////////////////
// DO NOT MOFIFY VALUES HERE
// They would be overridden by updates
// Instead, update the  "Configuration" notecard inside the prim

integer DEBUG = FALSE;

// string theme = "Terminal";
integer showPastEvents = FALSE;
string bannerURL = "http://2do.pm/events/banner-black.png";
string backgroundColor = "ff000000";
string fontColor = "ff33ff33";
string colorPast = "";
string colorStarted = "";
string colorSoon = "";
string colorToday = "";
string colorLater = "";
string colorHour = "";

string mainFontName = "Junction";
integer mainFontSize=16;

string hourFontName = "";
integer hourFontSize = 12;

float refreshTime = 1800;
integer updateWarning = TRUE;
integer sendSimInfo = FALSE;

integer lineHeight = 28;
integer cellPadding = 0;
integer bannerHeight = 90;
integer textureWidth = 512;
integer textureHeight = 512;
list activeSides = [ 2,4 ];

//////////////////////////
// internal, do not touch:

string CONFIG_FILE = "Configuration";

list events;
list eventIndices;
integer channel;
integer listenHandle;
integer listening = 0;
key httpRequest;
string httpSimInfo;
string httpUserAgent;
list avatarDestinations = [];
key initTKey="7fca4681-d388-4d69-971a-d884b4586f22";
float touchStarted;

// Change only in your master script
string scrupURL = "https://speculoos.world/scrup/scrup.php"; // Change to your scrup.php URL
integer scrupPin = 56748; // Change or not, it shouldn't hurt
integer scrupAllowUpdates = TRUE; // should always be true, except for debug

// Do not change below
string scrupRequestID;
string version;

debug(string message)
{
    if(DEBUG) llOwnerSay(message);
}

scrup() {
    string scrupVersion = "1.0.2";
    if(!scrupAllowUpdates)  {
        llSetRemoteScriptAccessPin(0);
        return;
    }

    // Get version from script name
    string name = llGetScriptName();
    string part;
    // list softParts=[];
    list parts=llParseString2List(name, [" "], "");
    integer i; for (i=1;i<llGetListLength(parts);i++)
    {
        part = llList2String(parts, i);
        string main = llList2String(llParseString2List(part, ["-"], ""), 0);
        if(llGetListLength(llParseString2List(main, ["."], [])) > 1
        && llGetListLength(llParseString2List(main, [".", 0,1,2,3,4,5,6,7,8,9], [])) == 0) {
            version = part;
            jump break;
        }
    }
    version = "";
    scrupAllowUpdates = FALSE;
    llSetRemoteScriptAccessPin(0);
    return;

    @break;
    list scriptInfo = [ llDumpList2String(llList2List(parts, 0, i - 1), " "), version ];
    string scriptname = llList2String(scriptInfo, 0);
    version = llList2String(scriptInfo, 1);

    if(llGetStartParameter() == scrupPin) {
        llOwnerSay(scriptname + " version " + version);
        // Delete other scripts with the same name. As we just got started after
        // an update, we should be the newest one.
        i=0; do {
            string found = llGetInventoryName(INVENTORY_SCRIPT, i);
            if(found != llGetScriptName()) {
                // debug("what shall we do with " + found);
                integer match = llSubStringIndex(found, scriptname + " ");
                if(match == 0) {
                    llOwnerSay("deleting duplicate '" + found + "'");
                    llRemoveInventory(found);
                }
            }
        } while (i++ < llGetInventoryNumber(INVENTORY_SCRIPT)-1);
    }

    list params = [ "loginURI=" + osGetGridLoginURI(), "action=register",
    "type=client", "linkkey=" + llGetKey(), "scriptname=" + scriptname,
    "pin=" + scrupPin, "version=" + version, "scrupVersion=" + scrupVersion ];
    scrupRequestID = llHTTPRequest(scrupURL, [HTTP_METHOD, "POST",
    HTTP_MIMETYPE, "application/x-www-form-urlencoded"],
    llDumpList2String(params, "&"));
    llSetRemoteScriptAccessPin(scrupPin);
}

integer boolean(string val)
{
    if(llToUpper(val) == "TRUE" | llToUpper(val) == "YES" | (integer)val == TRUE)
    {
        return TRUE;
    }
    return FALSE;
}

getConfig() {
    if(llGetInventoryType(CONFIG_FILE) == INVENTORY_NOTECARD) {
        string data = osGetNotecard(CONFIG_FILE);
        list lines = llParseString2List (data,["\n"],[]);
        integer i; for (i=0;i<llGetListLength (lines);i++)
        {
            string line = llList2String(lines,i);
            list parse  = llParseStringKeepNulls (line, ["="],[]);
            string var = llStringTrim(llList2String(parse, 0), STRING_TRIM);
            string val = llStringTrim(llList2String(parse, 1), STRING_TRIM);
            // if (var == "theme") theme = (string)val;
            if (var == "showPastEvents") showPastEvents = boolean(val);
            else if (var == "updateWarning") updateWarning = boolean(val);
            else if (var == "sendSimInfo") sendSimInfo = boolean(val);

            else if (var == "textureWidth" && val!="") textureWidth = (integer)val;
            else if (var == "textureHeight" && val!="") textureHeight = (integer)val;
            else if (var == "logoURL") bannerURL = (string)val;
            else if (var == "bannerURL") bannerURL = (string)val;
            else if (var == "bannerHeight") bannerHeight = (integer)val;
            else if (var == "lineHeight") lineHeight = (integer)val;
            else if (var == "cellPadding") cellPadding = (integer)val;

            else if (var == "mainFontName" && val!="") mainFontName = (string)val;
            else if (var == "mainFontSize" && val!="") mainFontSize = (integer)val;
            else if (var == "hourFontName") hourFontName = (string)val;
            else if (var == "hourFontSize" && val!="") hourFontSize = (integer)val;

            else if (var == "backgroundColor") backgroundColor = (string)val;
            else if (var == "fontColor") fontColor = (string)val;
            else if (var == "colorPast") colorPast = (string)val;
            else if (var == "colorStarted") colorStarted = (string)val;
            else if (var == "colorSoon") colorSoon = (string)val;
            else if (var == "colorToday") colorToday = (string)val;
            else if (var == "colorLater") colorLater = (string)val;
            else if (var == "colorHour") colorHour = (string)val;
        }
        if(backgroundColor == "transparent")
        backgroundColor = TEXTURE_TRANSPARENT;
    }

    if(hourFontName=="") hourFontName = mainFontName;
    if(fontColor=="") fontColor = "black";
    if(colorPast=="") colorPast = fontColor;
    if(colorStarted=="") colorStarted = fontColor;
    if(colorSoon=="") colorSoon = colorStarted;
    if(colorToday=="") colorToday = colorStarted;
    if(colorLater=="") colorLater = colorToday;
    if(colorHour=="") colorHour = fontColor;
}

//
// manipulate global avatarDestinations list
//
// insert or overwrite destination for agent with dest
//
tfSetAvatarDest(key agent, string dest)
{
    list newList = [];
    integer idx;
    integer len = llGetListLength(avatarDestinations)/2;
    integer set = FALSE;

    for(idx=0;idx<len;idx++) {
        key avatar = llList2Key(avatarDestinations, (idx*2));
        if(avatar==agent) {
            newList += [ agent, dest ];
            set = TRUE;
        } else {
            newList += [ avatar, llList2String(avatarDestinations, (idx*2)+1) ];
        }
    }
    if(!set) {
        newList += [ agent, dest ];
    }

    avatarDestinations = newList;
}

//
// retrieve avatar dest from global avatarDestination list
//
// returns hgurl if destination set, NULL_KEY otherwise
//
string tfGetAvatarDest(key agent)
{
    integer idx;
    integer len = llGetListLength(avatarDestinations)/2;

    for(idx=0;idx<len;idx++) {
        if(llList2Key(avatarDestinations, (idx*2))==agent) {
            return llList2String(avatarDestinations, (idx*2)+1);
        }
    }
    return NULL_KEY;
}

doRequest()
{
    string requestURL = "http://2do.pm/events/events.lsl2";
    if(sendSimInfo) requestURL+="?ref="+httpSimInfo;
    httpRequest = llHTTPRequest(requestURL + httpUserAgent, [HTTP_BODY_MAXLENGTH, 4096], "");
}

string tfTrimText(string in, string fontname, integer fontsize,integer width)
{
    integer i;
    integer trimmed = FALSE;

    for(;llStringLength(in)>0;in=llGetSubString(in,0,-2)) {

        vector extents = osGetDrawStringSize("vector",in,fontname,fontsize);

        if(extents.x<=width) {
            if(trimmed) {
                return in + "…";
            } else {
                return in;
            }
        }

        trimmed = TRUE;
    }

    return "";
}

refreshTexture()
{
    string commandList = "";

    eventIndices = [];

    commandList = osSetPenColor(commandList, colorStarted);
    commandList = osMovePen(commandList, 0, 0);
    if(bannerHeight > 0 && bannerURL != "")
    commandList = osDrawImage(commandList, 512, bannerHeight, bannerURL);

    commandList = osSetPenSize(commandList, 1);
    // commandList = osDrawLine(commandList, 0, 80, 512, 80);

    integer numEvents = llGetListLength(events)/3;

    integer i;

    integer y = bannerHeight;

    integer secondMargin = 10 + hourFontSize * 7;
    // rough estimation, but it works quite well

    integer notBefore = llGetUnixTime() - (2*3600);
    integer currentTime = llGetUnixTime();

    integer numEventsShown = 0;

    for(i=0;i<numEvents && numEventsShown<15;i++) {
        integer base = i*3;

        // this is a ~-seperated list of time specifiers
        // it has 6 fields, but may be extended with more fields in the
        // future
        // fields are start-time~start-date~start-timestamp~end-time~end-date~end-timestamp
        // timestamps are seconds since the unix epoch (January 1st 1970, 00:00 UTC)
        string timeSpecifier = llList2String(events, base+1);
        list timeParsed = llParseString2List(timeSpecifier, ["~"], []);


        if(showPastEvents || llList2Integer(timeParsed, 2) > notBefore) {
            eventIndices += i;
            if(llList2Integer(timeParsed, 2) < currentTime - 3600) {
                commandList = osSetPenColor(commandList, colorPast);
            }
            else if(llList2Integer(timeParsed, 2) < currentTime) {
                commandList = osSetPenColor(commandList, colorStarted);
            }
            else if(llList2Integer(timeParsed, 2) < currentTime + 4 * 3600) {
                commandList = osSetPenColor(commandList, colorSoon);
            }
            else if(llList2Integer(timeParsed, 2) < currentTime + 24 * 3600) {
                commandList = osSetPenColor(commandList, colorToday);
            }
            else {
                commandList = osSetPenColor(commandList, colorLater);
            }
            commandList = osMovePen(commandList, 10, y + 1 + cellPadding);
            commandList = osSetFontName(commandList, hourFontName);
            commandList = osSetFontSize(commandList, hourFontSize);
            commandList = osDrawText(commandList, llList2String(timeParsed, 0));

            string text = llList2String(events, base);
            text = tfTrimText(text, mainFontName, mainFontSize, textureWidth-30-secondMargin);
            commandList = osMovePen(commandList, secondMargin, y + cellPadding);
            commandList = osSetFontName(commandList, mainFontName);
            commandList = osSetFontSize(commandList, mainFontSize);
            commandList = osDrawText(commandList, text);

            y += lineHeight;

            numEventsShown++;
        }
    }

    integer alpha = 255;
    if(backgroundColor == TEXTURE_TRANSPARENT) alpha = 0;
    i = 0;
    do
    {
        integer drawSide=llList2Integer(activeSides, i);
        osSetDynamicTextureDataBlendFace("", "vector", commandList, "width:"+(string)textureWidth+",height:"+(string)textureHeight
        + ",bgcolor:" + backgroundColor
        + ",alpha:" + (string)alpha, FALSE,1, 0,alpha,drawSide);
        i++;
    }
    while (i < llGetListLength(activeSides));

 }

tfLoadURL(key avatar)
{
    llLoadURL(avatar, "Visit 2DO.pm/events for a detailed full list of upcoming events.", "http://2do.pm/events/");
}

// present dialog to avatar with hg / local choice, store destination
// keyed by avatar to retrieve when choice is made
tfGoToEvent(key avatar, integer eventIndex)
{
    integer numEvents = llGetListLength(events)/3;

    integer base = eventIndex * 3;

    if(eventIndex<numEvents) {
        string text="\n" + llList2String(events, base+0);

        text += "\n\n";

        text += "The hypergrid url for this event is:\n\n"+llList2String(events, base+2)+"\n\n";

        // text += "Is this hgurl a hypergrid url for you or a local url?\n\n";

        tfSetAvatarDest(avatar, llList2String(events, base+2));
        // llMapDestination(llList2String(events, base+2),<128,128,21>, ZERO_VECTOR);
        llDialog(avatar, text, ["Teleport", "Cancel"], channel);
        if(listening==0) {
            listenHandle = llListen(channel, "", NULL_KEY, "");
            listening = (integer)llGetTime();
        }
    } else {
    }
}
initTextures()
{
    integer i = 0;
    do
    {
        integer drawSide=llList2Integer(activeSides, i);
        llSetTexture(initTKey, drawSide);
        i++;
    }
    while (i < llGetListLength(activeSides));
}

default
{
    state_entry()
    {
        scrup();
        channel = -25673 - (integer)llFrand(1000000);
        getConfig();
        initTextures();

        listening = 0;
        avatarDestinations = [];
        llSetTimerEvent(refreshTime);
        httpUserAgent=" HTTP/1.0\nUser-Agent: LSL Script (Mozilla Compatible)" + "\n\n";
        if(sendSimInfo) httpSimInfo = llGetScriptName() + "/" + version + " " + osGetGridGatekeeperURI() + ":" + llGetRegionName();
        doRequest();
    }

    http_response(key requestID, integer status, list metadata, string body)
    {
        if(requestID == scrupRequestID) {
            debug("client register response " + (string)status + "\n" + body);
        }
        if(requestID == httpRequest) {
            if(status==200) {
                events = llParseString2List(body, ["\n"], []);

                // We don't use other meta information for now. We split them in prevision of future versions to ensure backwards compatibility between updated server export and outdated in-wolrd script
                string metaRaw = llList2String(events, 0);
                list meta = llParseString2List(metaRaw, ";", "");
                list versionList = llParseString2List(llList2String(meta, 0), " ", "");
                string remoteVersion = llList2String(version, 0);
                versionList = llDeleteSubList(versionList, 0, 0);
                string remoteMessage = llDumpList2String(versionList, " ");
                meta = llDeleteSubList(meta, 0, 0);

                // events = llDeleteSubList(events, 0, 0);
                // if(updateWarning)
                // {
                //     if(compareVersions(remoteVersion, version) > 0)
                //     {
                //         llOwnerSay(
                //         "A new version " + remoteVersion + " is available\n"
                //         + remoteMessage + "\n"
                //         + "Your version is " + version + "\n"
                //         + "Head over to Speculoos.world:8002:Lab region to get the updated board."
                //         + " hop://speculoos.world:8002/Lab/128/128/22"
                //         + " or visit Kitely Market https://www.kitely.com/market/product/50129545");
                //     }
                // }

                refreshTexture();
            } else {
                llOwnerSay("Unable to fetch event, status: "+(string)status);
            }
        }
    }

    listen(integer chan, string name, key agent, string msg)
    {
        if(chan==channel) {
            string dsturl = tfGetAvatarDest(agent);
            if(msg=="Teleport") {
                if(dsturl!=NULL_KEY) {
                    // if(msg=="Local grid") {
                    //     list hgurl = llParseString2List(dest, [":"], []);
                    //     dsturl = llList2String(hgurl, 2);
                    // }
                    osTeleportAgent(agent, dsturl, <128.0,128.0,23.0>, <1.0,1.0,0.0> );
                }
            // } else if(msg=="Map") {
            //     list dstList = llParseString2List(dsturl, [":"], []);
            //     // string destMap = "http://" + llList2String(dstList, 0) + ":" + llList2String(dstList, 1) + ":" + llList2String(dstList, 2);
            //     llInstantMessage(agent, "Opening map for " + dsturl);
            //     llMapDestination(dsturl, <128,128,21>, ZERO_VECTOR);
            } else if (msg!="Cancel") {
                llInstantMessage(agent, msg + " not implemented yet");
            }
        }
    }
    touch_start(integer index)
    {
        touchStarted=llGetTime();
    }
    touch_end(integer num)
    {
        if(llDetectedKey(0)==llGetOwner() && llGetTime() - touchStarted > 2)
        llResetScript();

        integer i;
        for(i=0;i<num;i++) {
            integer link = llDetectedLinkNumber(i);
            if (link != llGetLinkNumber()) jump break;

            vector point = llDetectedTouchST(i);
            if (point == TOUCH_INVALID_TEXCOORD)jump break;

            integer face = llDetectedTouchFace(i);
            if (activeSides != [ALL_SIDES] && llListFindList(activeSides, face) == -1) {
                jump break;
            }

            vector touchPos = llDetectedTouchUV(i);
            integer touchX = (integer)(touchPos.x * textureWidth);
            integer touchY = textureHeight - (integer)(touchPos.y * textureHeight);
            key avatar = llDetectedKey(i);

            if(touchY < bannerHeight) {
                tfLoadURL(avatar);
            } else {
                integer touchIndex;
                integer eventIndex;

                touchIndex = (integer)((touchY - bannerHeight) / lineHeight);

                if(touchIndex < llGetListLength(eventIndices)) {
                    eventIndex = llList2Integer(eventIndices, touchIndex);
                    tfGoToEvent(avatar, eventIndex);
                }
            }
        }
        @break;
    }

    timer()
    {
            // timeout listener
        if(listening!=0) {
            if( (listening + 300) < (integer)llGetTime() ) {
                llListenRemove(listenHandle);
                avatarDestinations=[];
                listening = 0;
            }
        }
            // refresh texture
        doRequest();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if(change & CHANGED_SHAPE ||
           change & CHANGED_SCALE ||
           change & CHANGED_OWNER ||
           change & CHANGED_REGION
           ) {
               llResetScript();
        }
    }
}
