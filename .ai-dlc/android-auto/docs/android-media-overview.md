# Media apps for cars overview

This guide assumes you have a media app that plays audio on a phone and that your media app conforms to Android media app architecture. You'll also learn what your app needs from `MediaBrowserService` or `MediaLibraryService` and `MediaSession` to run on Android Auto or AAOS. Once you've completed the core media infrastructure, you can add support for Android Auto and AAOS to your media app.

**Caution:** Google takes driver distraction seriously. Your app must meet specific design requirements before it can be listed on Google Play for Android Auto or AAOS. By adhering to these requirements, you can make it more straightforward to build and test your app. To learn more, see [Android app quality for cars](/docs/quality-guidelines/car-app-quality?category=media).

## Contents

These pages detail how to work with the media apps:

- [Configure the manifest file](/training/cars/media/configure-manifest)
- [Enable playback controls](/training/cars/media/enable-playback)
- [Support voice actions](/training/cars/media/voice-actions)
- [Implement distraction safeguards](/training/cars/media/distraction-safeguards)
- [Handle errors](/training/cars/media/errors)

## Create audio media apps

If your app focuses on playing audio media, use the tools described here. You can create media apps for cars in one of two ways:

1.  Use `MediaBrowserService` and a `MediaSession` to create an app that Android Auto and AAOS can connect to. This allows the infotainment screen interface to render media browsing and playback user interfaces optimized for in-car use.

    *or*

2.  Use the [Cars App Library](/training/cars/apps) templates to build apps with a customized media browsing and playback experience, including custom actions. To learn more, see [Build a templated media app](/training/cars/apps/media).

**Note:** The Car App Library templates still require a `MediaSession` and either a `MediaBrowserService` or `MediaLibraryService` to maintain support for voice actions and other smart experiences.

**Caution:** Aside from [voice guidance audio for navigation apps](/training/cars/apps/navigation#voice-guidance) and the media apps described here, in-app media playback while driving isn't permitted.

This guide assumes you have a media app that plays audio on a phone and that your media app conforms to Android [media app architecture](/media/legacy). This guide describes the required components of a `MediaBrowserService` or `MediaLibraryService` and `MediaSession` needed by your app to be compatible with Android Auto or AAOS. After you complete the core media infrastructure, you can [add support for Android Auto](/training/cars/media/auto) and [add support for AAOS](/training/cars/media/automotive-os) to your media app.

## Create video media apps

If the primary content provided by your app is video, see:

- [Build video apps for Android Automotive OS](/training/cars/parked/video)
- [Build parked apps for cars](/training/cars/parked)

## Before you start

Be sure to consult:

- [Android media API documentation](/media/legacy)
- Design guidance: [Create media apps](/design/ui/cars/guides/app-types/create-media-apps)
- Terminology: [Key terms and concepts](#terms-concepts)

## Learn key terms and concepts

These terms are used in relation to building media apps for cars:

Media browser  
An API used by media apps to discover media browser services and to display their content. Android Auto and AAOS use a media browser to find your app's media browser service.

Media browser service  
An Android service implemented by your media app that complies with the [`MediaBrowserServiceCompat`](/reference/android/support/v4/media/MediaBrowserCompat) API. Your app uses this service to expose content. We also support [`MediaLibraryService`](/media/media3/session/serve-content).

Media item  
The media browser organizes content in a tree of [`MediaItem`](/training/cars/parked/video) objects. A media item can have one or both of these flags. A media item that can be browsed for **and** played operates like a playlist. You can select the item to play all of its descendants, or you can browse its descendants.

- `FLAG_PLAYABLE` indicates that the item is a leaf on the content tree. The item represents a single sound stream, such as a song on an album, a chapter in an audio book, or an episode of a podcast.

- `FLAG_BROWSABLE` indicates that the item is a node on the content tree and has descendants. For example, the item represents an album, and its descendants are the songs on the album.

## See additional resources

For additional information, see:

- [Universal Media Player sample](//github.com/googlesamples/android-UniversalMusicPlayer)
- [Audio app overview](/media/legacy/audio)
- [ExoPlayer overview](/media/media3/exoplayer)
