// 2DO board
//
//
// In-word teleporter board for 2DO events server.
//
// * Get the latest version in-world at Speculoos Lab:
//	hop://speculoos.world:8002/Lab
// * or from git repository
//	https://github.com/GuduleLapointe/2do-board
//
// Licence: GPLv3
// © 2018-2019 Gudule Lapointe <gudule@speculoos.world>
//   Initial project author: Tom Frost <tomfrost@linkwater.org>

////////////////////////////
// DO NOT MOFIFY VALUES HERE
// They would be overridden by updates
// Instead, update the  "Configuration" notecard inside the prim

integer DEBUG = TRUE;

// string theme = "Terminal";
integer showPastEvents = FALSE;

string teleportMethod = "teleport"; // {dialog|map|teleport} // Default dialog

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
//list activeSides = [ 2,4 ];
list activeSides = [ 0,1,2,3,4,5 ];
//list activeSides = ALL_SIDES; // Unless the object is a perfect cube, use explicit list instead

// Set renderer="png" to use the server-side PNG board image instead of osDrawText.
// ratio = board face width/height (e.g. 0.75 for a 1.5×2 m board, 1.0 for square).
// Set ratio=0 to auto-detect from prim scale.
string renderer = "";
float ratio = 0.0; // Leave 0.0 to calculate ratio from actual faces dimensions
float ratioCap = 0.25; // Do not update face if ratio is extreme (side faces)

// Events source URL. Default points to 2do.directory public aggregator.
// Override in Configuration notecard to use your own source.
string eventsURL = "https://2do.directory/events/events.php";

//////////////////////////
// internal, do not touch:

string bannerLink = "https://2do.directory/events/";
string bannerImageURL = "https://2do.directory/events/banner-black.png";

string CONFIG_FILE = "Configuration";

key initTKey="7fca4681-d388-4d69-971a-d884b4586f22";
vector defaultLandingPoint = <128.0, 128.0, 23.0>;
vector defaultLookAt = <1.0, 1.0, 0.0>;

string gatekeeperURI;
list events;
list eventIndices;
integer channel;
integer listenHandle;
integer listening = 0;
key httpRequest;
string httpSimInfo;
string httpUserAgent;
list avatarDestinations = [];
float touchStarted;

// Change only in your master script
string scrupURL = "https://speculoos.world/scrup/scrup.php"; // Change to your scrup.php URL
integer scrupPin = 56748; // Change or not, it shouldn't hurt
integer scrupAllowUpdates = TRUE; // should always be true, except for debug

// Do not change below
string scrupRequestID;
string version;

// Clickmap cache — parallel lists keyed by ratioStr ("1.0", "0.5", "osdraw", …)
list clickmapRatios = [];
list clickmapData   = [];   // one full response string per ratio

// Texture UUID cache — parallel lists keyed by ratioStr
list textureRatios = [];
list textureIDs	= [];

// Inflight clickmap requests — strided list [requestKey, ratioStr, …]
list clickmapRequests = [];

debug(string message)
{
	if(DEBUG) llOwnerSay(message);
}

scrup() {
	debug("checking available updates");
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
		// Normalize key: lowercase, strip underscores — accepts old ALL_CAPS_UNDERSCORE and new camelCase
		var = llToLower(llDumpList2String(llParseString2List(var, ["_"], []), ""));
		// if (var == "theme") theme = (string)val;
		if (var == "showpastevents") showPastEvents = boolean(val);
		else if (var == "updatewarning") updateWarning = boolean(val);
		else if (var == "sendsiminfo") sendSimInfo = boolean(val);

		else if (var == "texturewidth" && val!="") textureWidth = (integer)val;
		else if (var == "textureheight" && val!="") textureHeight = (integer)val;
		else if (var == "logourl") bannerImageURL = (string)val;
		else if (var == "bannerImageURL") bannerImageURL = (string)val;
		else if (var == "bannerheight") bannerHeight = (integer)val;
		else if (var == "lineheight") lineHeight = (integer)val;
		else if (var == "cellpadding") cellPadding = (integer)val;

		else if (var == "mainfontname" && val!="") mainFontName = (string)val;
		else if (var == "mainfontsize" && val!="") mainFontSize = (integer)val;
		else if (var == "hourfontname") hourFontName = (string)val;
		else if (var == "hourfontsize" && val!="") hourFontSize = (integer)val;

		else if (var == "eventsurl" && val!="") eventsURL = (string)val;
		else if (var == "renderer") renderer = llToLower((string)val);
		else if (var == "ratio" && val!="") ratio = (float)val;
		else if (var == "ratiocap" && val!="") ratioCap = (float)val;

		else if (var == "backgroundcolor") backgroundColor = (string)val;
		else if (var == "fontcolor") fontColor = (string)val;
		else if (var == "colorpast") colorPast = (string)val;
		else if (var == "colorstarted") colorStarted = (string)val;
		else if (var == "colorsoon") colorSoon = (string)val;
		else if (var == "colortoday") colorToday = (string)val;
		else if (var == "colorlater") colorLater = (string)val;
		else if (var == "colorhour") colorHour = (string)val;
		else if (var == "activesides" && val!="") activeSides = llParseString2List(val, [",","]","["," "], []);
		else if (var == "teleportmethod" && val!="") teleportMethod = (string)val;
		}
		if (backgroundColor == "transparent") {
			backgroundColor = TEXTURE_TRANSPARENT;
		}
	}

	debug("renderer: " + renderer);

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
setAvatarDest(key agent, string dest)
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
// returns teleportURL if destination set, NULL_KEY otherwise
//
string getAvatarDest(key agent)
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

float getFaceRatio(integer face)
{
	// Bypass calculation to honor custom ratio if configured
	if (ratio > 0) return ratio;

	integer primType = llList2Integer(llGetPrimitiveParams([PRIM_TYPE]), 0);
	if (primType == PRIM_TYPE_BOX) {
		vector scale = llGetScale();
		if (face == 0 || face == 5) return scale.x / scale.y;  // top, bottom
		if (face == 1 || face == 3) return scale.x / scale.z;  // front, back
		if (face == 2 || face == 4) return scale.y / scale.z;  // left, right
	}
	return 1.0;
}

// Returns the face ratio if valid per ratioCap, or -1 to signal the face should be skipped.
float getValidFaceRatio(integer face)
{
	float faceRatio = getFaceRatio(face);
	if (ratioCap > 0 && (faceRatio < ratioCap || faceRatio > 1.0/ratioCap)) {
		return -1;
	}
	return faceRatio;
}

refreshEvents()
{
	clickmapRatios = [];
	clickmapData   = [];
	if (renderer == "png") {
		refreshTexturePNG();
		return;
	}
	string url = eventsURL + "?format=lsl2";
	if (sendSimInfo) url += "&ref=" + httpSimInfo;
	httpRequest = llHTTPRequest(url + httpUserAgent, [HTTP_BODY_MAXLENGTH, 4096], "");
}

string trimText(string in, string fontname, integer fontsize,integer width)
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

refreshTexturePNG()
{
	debug("fetching PNG texture from server " + eventsURL);

	string dynamicID = ""; // not implemented yet
	string contentType = "image";
	string extraParams = "width:" + (string)textureWidth + ",height:" + (string)textureHeight;
	integer timer = 0;	// timer is not implemented yet in OSSL
	integer alpha = 255;  // 0 = 100% Transparent 255 = 100% Solid
	integer blend = TRUE; // TRUE = the newly generated texture is iBlended with the appropriate existing ones on the prim
	integer disp = 2;	// 1 = expire deletes the old texture.  2 = temp means that it is not saved to the Database.

	list textureCache;

	integer i = 0;
	do
	{
		integer face = llList2Integer(activeSides, i);

		float faceRatio = getValidFaceRatio(face);
		float renderRatio = faceRatio;
		if (faceRatio > 0) {
			renderRatio = faceRatio * (float)textureHeight / (float)textureWidth;
		} else {
			// Better safe than sorry
			faceRatio = 1.0;
		}

		// Set common query args for both clickkmap and png urls
		string queryArgs = "&ratio=" + renderRatio
			+ "&width=" + (string)textureWidth
			+ "&height=" + (string)textureHeight;

		// Request Clickmap request first, as it's asynchronous, we might
		// save some time (or not). Make sure to send only one request per ratio
		if(llListFindList(clickmapRequests, [faceRatio]) < 0) {
			//debug("request clickmap for ratio " + faceRatio + " (" + renderRatio + ")");
			string clickmapURL = eventsURL + "?format=clickmap" + queryArgs;
			key clickmapRequestID = llHTTPRequest(clickmapURL + httpUserAgent, [HTTP_BODY_MAXLENGTH, 16384], "");
			clickmapRequests += [clickmapRequestID,faceRatio];
		}

		// Set texture
		key cachedTexture = NULL_KEY;
		integer cachedTextureIdx = llListFindList(textureCache, [faceRatio]);
		if(cachedTextureIdx >=0) {
			cachedTexture = llList2String(textureCache, cachedTextureIdx + 1);
		}
		if (cachedTexture != NULL_KEY) {
			debug("face " + face + " ratio " + faceRatio + " cached " + cachedTexture);
			dynamicID = cachedTexture;
			// TODO: Use existing texture when proper caching is implemented
			// llSetTexture(cachedTexture, face);
		} else {
			debug("face " + face + " ratio " + faceRatio + " never seen, new call");
		}
		string url = eventsURL + "?format=png" + queryArgs;
		string newDynamicID = osSetDynamicTextureURLBlendFace( dynamicID, contentType, url, extraParams, blend, disp, timer, alpha, face );

		// TODO: get generated texture UUID by prim properties:
		// 		osSetDynamicTextureURLBlendFace() return value does not seem to
		//		be implemented (return value is null key), doc mentions it returns a string
		//if(llListFindList(textureCache, [ratio]) < 0 ) {
		//	debug("caching face " + face + " ratio " + faceRatio + " " + cachedTexture);
		//	textureCache += [faceRatio, textureCache];
		//}

		i++;
	}
	while (i < llGetListLength(activeSides));
}

refreshTexture()
{
	refreshTextureOsDraw();
}

refreshTextureOsDraw()
{
	debug("generate texture with OSSL osDraw");
	string commandList = "";

	eventIndices = [];

	commandList = osSetPenColor(commandList, colorStarted);
	commandList = osMovePen(commandList, 0, 0);
	if (bannerHeight > 0 && bannerImageURL != "") {
		commandList = osDrawImage(commandList, 512, bannerHeight, bannerImageURL);
	}

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


		if (showPastEvents || llList2Integer(timeParsed, 2) > notBefore) {
			eventIndices += i;
			integer startTime = llList2Integer(timeParsed, 2);
			if (startTime < currentTime - 3600) {
				commandList = osSetPenColor(commandList, colorPast);
			} else if (startTime < currentTime) {
				commandList = osSetPenColor(commandList, colorStarted);
			} else if (startTime < currentTime + 4 * 3600) {
				commandList = osSetPenColor(commandList, colorSoon);
			} else if (startTime < currentTime + 24 * 3600) {
				commandList = osSetPenColor(commandList, colorToday);
			} else {
				commandList = osSetPenColor(commandList, colorLater);
			}
			commandList = osMovePen(commandList, 10, y + 1 + cellPadding);
			commandList = osSetFontName(commandList, hourFontName);
			commandList = osSetFontSize(commandList, hourFontSize);
			commandList = osDrawText(commandList, llList2String(timeParsed, 0));

			string text = llList2String(events, base);
			text = trimText(text, mainFontName, mainFontSize, textureWidth - 30 - secondMargin);
			commandList = osMovePen(commandList, secondMargin, y + cellPadding);
			commandList = osSetFontName(commandList, mainFontName);
			commandList = osSetFontSize(commandList, mainFontSize);
			commandList = osDrawText(commandList, text);

			y += lineHeight;
			numEventsShown++;
		}
	}

	integer alpha = 255;
	if (backgroundColor == TEXTURE_TRANSPARENT) {
		alpha = 0;
	}
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

	// Build clickmap for the classic renderer (UV fractions from top, 0=top 1=bottom)
	float bannerFrac = (float)bannerHeight / (float)textureHeight;
	string clickmapLines = "~0.0~" + (string)bannerFrac + "\n";  // banner sentinel (empty teleportURL)
	integer numShown = llGetListLength(eventIndices);
	integer ei;
	for (ei = 0; ei < numShown; ei++) {
		float rowY0 = bannerFrac + (float)ei * (float)lineHeight / (float)textureHeight;
		float rowY1 = rowY0 + (float)lineHeight / (float)textureHeight;
		integer evIdx = llList2Integer(eventIndices, ei);
		string teleportURL = llList2String(events, evIdx * 3 + 2);
		clickmapLines += teleportURL + "~" + (string)rowY0 + "~" + (string)rowY1 + "\n";
	}
	integer existing = llListFindList(clickmapRatios, ["osdraw"]);
	if (existing != -1) {
		clickmapData = llListReplaceList(clickmapData, [clickmapLines], existing, existing);
	} else {
		clickmapRatios += ["osdraw"];
		clickmapData   += [clickmapLines];
	}
 }

openWebPage(key avatar)
{
	if(DEBUG) {
		debug("openWebPage → " + bannerLink);
		return;
	}
	llLoadURL(avatar, "Visit 2DO.pm/events for a detailed full list of upcoming events.", bannerLink);
}

teleportRoute(key avatar, string teleportURL)
{
	debug("teleportRoute → " + teleportURL);
	if(teleportMethod == "map") {
		teleportMap(teleportURL);
		return;
	} else if(teleportMethod == "teleport") {
		teleportAvatar(avatar, teleportURL);
		return;
	}

	//debug("teleportDialog → " + teleportURL);
	// No direct tp/map, require dialog confirmation
	setAvatarDest(avatar, teleportURL);
	llDialog(avatar, "\n" + teleportURL + "\n\n", ["Teleport", "Cancel"], channel);
	if(listening==0) {
		listenHandle = llListen(channel, "", NULL_KEY, "");
		listening = (integer)llGetTime();
	}
}

teleportAvatar(key avatar, string teleportURL) {
	// TODO: extract landingPoint from url if provided
	vector landingPoint = defaultLandingPoint;
	vector lookAt = defaultLookAt;
	if (teleportURL != NULL_KEY) {
		//debug( "disabled for debug: osTeleportAgent(" + avatar + ", " + teleportURL);
		//if(DEBUG) return;
		osTeleportAgent(avatar, teleportURL, landingPoint, lookAt);
		return;
	}
	debug("teleportAvatar called with null key");
}

teleportMap(string teleportURL) {
	//debug("teleportMap → " + teleportURL);
	// TODO: extract landingPoint from url if provided
	vector landingPoint = defaultLandingPoint;
	vector lookAt = defaultLookAt;
	llMapDestination(teleportURL, landingPoint, ZERO_VECTOR);
}

string strReplace(string str, string search, string replace) {
    return llDumpList2String(llParseStringKeepNulls((str),[search],[]),replace);
}

initTextures()
{
	integer i = 0;
	do
	{
		integer face = llList2Integer(activeSides, i);
		if (getValidFaceRatio(face) > 0) {
			llSetTexture(initTKey, face);
		}
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
		gatekeeperURI = strReplace(osGetGridGatekeeperURI(), "http://", "");
		//debug("gatekeeperURI " + gatekeeperURI);
		getConfig();
		initTextures();

		listening = 0;
		avatarDestinations = [];
		llSetTimerEvent(refreshTime);
		httpUserAgent=" HTTP/1.0\nUser-Agent: LSL Script (Mozilla Compatible)" + "\n\n";
		if(sendSimInfo) httpSimInfo = llGetScriptName() + "/" + version + " " + osGetGridGatekeeperURI() + ":" + llGetRegionName();
			refreshEvents();
	}

	http_response(key requestID, integer status, list metadata, string body)
	{
		if(requestID == scrupRequestID) {
			debug("client register response " + (string)status + "\n" + body);
		}

		integer clickmapIdx = llListFindList(clickmapRequests, [requestID]);
		if (clickmapIdx != -1) {
			string ratioStr = llList2String(clickmapRequests, clickmapIdx + 1);
			clickmapRequests = llDeleteSubList(clickmapRequests, clickmapIdx, clickmapIdx + 1);
			if (status == 200) {
				integer existing = llListFindList(clickmapRatios, [ratioStr]);
				if (existing != -1) {
					clickmapData = llListReplaceList(clickmapData, [body], existing, existing);
				} else {
					clickmapRatios += [ratioStr];
					clickmapData   += [body];
				}
				//debug("clickmap received for ratio " + ratioStr);
			} else {
				debug("clickmap error " + (string)status + " for ratio " + ratioStr);
			}
			return;
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

				events = llDeleteSubList(events, 0, 0);
				// if(updateWarning)
				// {
				//	if(compareVersions(remoteVersion, version) > 0)
				//	{
				//		llOwnerSay(
				//		"A new version " + remoteVersion + " is available\n"
				//		+ remoteMessage + "\n"
				//		+ "Your version is " + version + "\n"
				//		+ "Head over to Speculoos.world:8002:Lab region to get the updated board."
				//		+ " hop://speculoos.world:8002/Lab/128/128/22"
				//		+ " or visit Kitely Market https://www.kitely.com/market/product/50129545");
				//	}
				// }

				refreshTexture();
			} else {
				llOwnerSay("Unable to fetch event, status: "+(string)status);
			}
		}
	}

	listen(integer chan, string name, key agent, string msg)
	{
		if (chan == channel) {
			string teleportURL = getAvatarDest(agent);
			if (msg == "Teleport") {
				teleportAvatar(agent, teleportURL);
			} else if (msg == "Map") {
				teleportMap(teleportURL);
			} else if (msg != "Cancel") {
				llInstantMessage(agent, msg + " is not a valid choice");
			}
		}
	}
	touch_start(integer index)
	{
		touchStarted=llGetTime();
	}
	touch_end(integer num)
	{
		if(llDetectedKey(0)==llGetOwner() && llGetTime() - touchStarted > 2) {
			llResetScript();
		}

		integer i; // Loop is probably overengineering, 0 should be be enough
		for(i=0;i<num;i++) {
			integer link = llDetectedLinkNumber(i);
			vector point = llDetectedTouchST(i);
			integer face = llDetectedTouchFace(i);
			key avatar = llDetectedKey(i);

			if (link != llGetLinkNumber()) {
				debug("ignore other prim link " + (string)link);
				return;
			}
			if (point == TOUCH_INVALID_TEXCOORD) {
				debug("TOUCH_INVALID_TEXCOORD " + (string)point);
				return;
			}
			if (activeSides != [ALL_SIDES] && llListFindList(activeSides, face) == -1) {
				debug("ignore inactive face " + (string)face);
				return;
			}

			// UV fraction from top (0=top, 1=bottom); llDetectedTouchST returns <s,t,0>, t=.y
			float touchV = 1.0 - llDetectedTouchST(i).y;
			string ratioKey;

			if (renderer == "png") {
				float faceRatio = getValidFaceRatio(face);
				if (faceRatio <= 0) {
					debug("invalid face ratio " + (string)faceRatio);
					return;
				}
				ratioKey = (string)(faceRatio * (float)textureHeight / (float)textureWidth);
			} else {
				ratioKey = "osdraw";
			}

			integer clickmapIdx = llListFindList(clickmapRatios, [ratioKey]);
			if (clickmapIdx == -1) {
				debug("no clickmap for ratio " + (string)ratioKey);
				return;
			}

			debug("touch face=" + (string)face + " V=" + (string)touchV + " ratio=" + ratioKey);
			list clickmapLines = llParseString2List(llList2String(clickmapData, clickmapIdx), ["\n"], []);
			integer li;
			for (li = 0; li < llGetListLength(clickmapLines); li++) {
				string clickmapLine = llList2String(clickmapLines, li);
				if (clickmapLine == "") {
					// skip trailing newline — not an error
				} else {
					list parts = llParseString2List(clickmapLine, ["~"], []);
					if (llGetListLength(parts) < 3) {
						debug("invalid clickmap line: [" + clickmapLine + "]");
					} else {
						float rowY0 = (float)llList2String(parts, 1);
						float rowY1 = (float)llList2String(parts, 2);
						if (touchV >= rowY0 && touchV <= rowY1) {
							string teleportURL = llList2String(parts, 0);
							if (teleportURL == "") {
								openWebPage(avatar);
							} else {
								teleportRoute(avatar, teleportURL);
							}
							return;
						}
					}
				}
			}
			debug("not a clickable region (face=" + (string)face + " V=" + (string)touchV + ")");
		}
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
		refreshEvents();
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
