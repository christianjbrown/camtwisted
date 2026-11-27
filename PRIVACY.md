# CamTwisted and your privacy 🔒

The short version: CamTwisted collects nothing. There are no accounts, no analytics, no
adverts and no tracking. What you make stays on your Mac unless you send it somewhere yourself.

## What the app uses, and why

| What | Why | Where it goes |
| --- | --- | --- |
| Camera | To show your camera in a scene | Nowhere, unless you switch on an output |
| Microphone | To carry sound with the picture | Nowhere, unless you switch on an output |
| Speech recognition | Only when you add Live Captions, to write down what you say | Nowhere: it runs on your Mac, and the words are shown and then forgotten |
| Screen and windows | Only when you add a Screen or Window source | Nowhere, unless you switch on an output |
| Local network | To find a Chromecast or Apple TV, and to serve a stream to devices on your network | Only the devices you choose |
| Files you pick | Pictures, videos and setup files you open | They are read where they are, and not copied or uploaded |
| Keychain | To keep the password of a computer you watch over VNC | It stays in your Mac's keychain |

## What leaves your Mac

Only what you switch on in the Output tab:

- The **virtual camera** and **virtual microphone** hand the picture and sound to other apps
  on your Mac, such as a video call. What those apps do with it is up to them.
- A **web stream**, **AirPlay** or **Cast** sends the picture to devices on your own network.
- An **RTMP stream** sends the picture to the streaming service whose address you typed.
- A **recording** or a **snapshot** is saved as a file on your Mac.

Sources that come from elsewhere fetch only what you point them at: a web page, a stream's
address, or another computer over VNC.

## What is kept

- A setup file you save holds your scenes and settings. It never holds your stream key or a
  VNC password, so it is safe to share.
- Your snapshot folder and stream key are kept in the app's preferences on your Mac.

## Questions

Open an issue on this repository's Issues page.
