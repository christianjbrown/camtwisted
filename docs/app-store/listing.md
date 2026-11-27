# Mac App Store listing

Everything App Store Connect asks for when the app's page is set up, ready to paste in.
Primary language: English (U.K.). The screenshots are in `screenshots/`, at 2880 by 1800.

## App information

| Field | Value |
| --- | --- |
| Name (30 characters at most) | CamTwisted |
| Subtitle (30 at most) | Virtual camera with scenes |
| Primary category | Photo & Video |
| Secondary category | Productivity |
| Age rating | 4+: every answer in the questionnaire is No or None (see below) |
| Copyright | The year and the name of whoever publishes it |

## Promotional text (170 characters at most)

Mix cameras, screens, videos, titles and effects into scenes, then use them as your webcam in any call, or stream them. Switch scenes with a click, a key or a timer.

## Description

CamTwisted turns your Mac into a small television studio.

Build a picture out of cameras, screens, windows, videos, pictures and text. Add effects. Then use the result as your webcam in Zoom, Google Meet, Microsoft Teams, FaceTime or any other app, or send it to a live stream.

SCENES
Make as many scenes as you like: just you, your slides with you in the corner, a "back in five minutes" card. One is on air. Put another on air with a click, with a cut or a transition. Lock the scenes you never want to change by accident.

SOURCES
Any webcam. A whole screen, part of one, or a single window. Videos and playlists. Slide shows. Web pages. Live streams. Pictures, text in any font, and shapes. A pen for drawing on the picture.

EFFECTS
Titles, a news headline, a clock and a countdown. Live captions that write down what is said, by you or in a video, as it is said, on your Mac. Blur the background, or remove it with no green screen. Let the picture follow you as you move about. Become a toy figure whose face copies yours, grow a pair of alien antennae, put on pixel sunglasses or a moustache, or give yourself big eyes. Play it back in slow motion or as a stop motion film. Looks such as black and white, sepia, comic book and charcoal sketch. Crop, mask, mirror and kaleidoscope. Wrap the picture round a cube or a sphere. Every effect has a preview, and you can load your own.

MAKE IT YOURS
Drag things about on the picture itself: the middle to move, a corner to resize, the knob to turn. Shrink any source into a corner, tilt it, and set it moving. Give one source effects of its own.

WHERE IT GOES
A virtual camera for your calls. A stream for a live channel. A stream for browsers on your network. An Apple TV, a Chromecast, or a second screen. A recording in the file, encoding and quality you choose. Each at its own size, from 360p to 4K.

A STUDIO WINDOW
See what is on air beside what is next, with every scene one click away. Choose how the switch happens, from a straight cut to a dissolve, a page curl or a ripple, then go live.

SWITCH FROM ANYWHERE
Give each scene a keyboard shortcut that works from any app, so you can change scenes without leaving your call or your slides. Or let a scene hand over to the next one by itself after as long as you like.

SAVE YOUR SHOW
Save everything as a file and open it again with a double-click. Switch on autosave and every change goes into the file as you make it. Not sure where to start? Open the example show from the File menu and take it apart.

CamTwisted is inspired by CamTwist, a Mac app from the 2000s. It is an independent project, written from scratch, and is not affiliated with or endorsed by the makers or owners of CamTwist.

## Keywords (100 characters at most, separated by commas)

virtual camera,webcam,streaming,scenes,effects,overlay,green screen,chroma key,background,rtmp

Other apps' names (Zoom, Meet, Teams) stay out of the keywords: App Review rejects them there.
The description may name them, because it says the app works with them.

## What's New in This Version

The first version.

## Addresses the page needs

These have to be public, so they work once the repository is public.

| Field | What goes there |
| --- | --- |
| Support URL | The repository's Issues page |
| Marketing URL (optional) | The repository's front page, which shows the README |
| Privacy Policy URL | `PRIVACY.md` in the repository |

## App privacy

Data collection: none. The app has no accounts, no analytics and no advertising, and nothing
leaves the Mac except the streams the person switches on. Live Captions use the Mac's own speech
recognition, held to the device, so speech is never sent anywhere.

## Notes for App Review

CamTwisted provides a virtual camera through a Camera Extension. To see it working:

1. Open the app. It starts on one scene with the Mac's camera.
2. On the Output tab, click Install camera, then allow it in System Settings under General,
   Login Items & Extensions, Camera Extensions.
3. Open FaceTime or Photo Booth and choose "CamTwisted Virtual Camera output" as the camera.
4. Back in CamTwisted, add an effect from "Add an effect": the other app shows the change.
5. To see Live Captions, add a Microphone source, then the Live Captions effect below it, and
   speak: the words appear along the bottom of the picture.

The app uses the camera and microphone as sources for the picture and its sound, and speech
recognition, on the device only, when the person adds Live Captions. It records the
screen only when the person adds a Screen or Window source, and uses the local network only
for the streams and devices the person switches on.

The virtual microphone needs an audio driver, which store apps cannot install, so it is offered
separately.

Sign-in required: no. There are no accounts.

## Age rating answers

Every question is answered No, or None for the ones that ask how often:

- In-app controls: no parental controls, no age assurance.
- Capabilities: no unrestricted web access (the Website source shows one page as a picture and
  cannot be browsed), no user-generated content, social media, messaging, shared location or
  advertising.
- Mature themes, medical or wellness, sexuality or nudity, violence, and chance-based
  activities: none.

That gives 4+.

## Content rights

"Yes, it contains, shows, or accesses third-party content, and I have the necessary rights."
The app ships no third-party pictures. The third-party content is whatever pages, streams and
files the person points the app at.

## Version

The store version is 0.1.0, the same as the build's version, because App Store Connect matches
a build to a version by that string.

## Screenshots

Each one is a headline over the real app, at 2880 by 1800. The pictures in them are NASA
photographs, which are in the public domain. Keep other companies' marks out of them: no BBC
test card and no toy figure. Effects keep the names the app gives them, Matrix included.

| File | Headline | What it shows |
| --- | --- | --- |
| `screenshots/1-scenes.jpg` | A TV studio on your Mac | The window: the picture, and scenes with their steps |
| `screenshots/2-remove-background.jpg` | Remove the background. No green screen. | A photo beside the same person on air in front of the Earth |
| `screenshots/3-effects.jpg` | Effects people will remember | Six effects on one picture |
| `screenshots/4-studio.jpg` | Line it up. Then go live. | The studio window: preview, on air, transitions and scenes |
| `screenshots/5-outputs.jpg` | Your webcam in every call | Where the picture goes |
| `screenshots/6-shortcuts.jpg` | Switch scenes from any app | A scene's shortcut and timer, with key caps for three scenes |
