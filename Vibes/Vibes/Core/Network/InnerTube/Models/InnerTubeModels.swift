import Foundation

// MARK: - Common Models

struct Thumbnail: Codable {
    let url: String
    let width: Int?
    let height: Int?
}

struct Run: Codable {
    let text: String
}

struct YTText: Codable {
    let runs: [Run]?

    var combined: String {
        runs?.map { $0.text }.joined() ?? ""
    }
}

struct NavigationEndpoint: Codable {
    let browseEndpoint: BrowseEndpoint?
    let watchEndpoint: WatchEndpoint?
    let watchPlaylistEndpoint: WatchPlaylistEndpoint?

    struct BrowseEndpoint: Codable {
        let browseId: String
        let params: String?
        let browseEndpointContextSupportedConfigs: BrowseEndpointContextSupportedConfigs?

        struct BrowseEndpointContextSupportedConfigs: Codable {
            let browseEndpointContextMusicConfig: BrowseEndpointContextMusicConfig?

            struct BrowseEndpointContextMusicConfig: Codable {
                let pageType: String?
            }
        }
    }

    struct WatchEndpoint: Codable {
        let videoId: String
        let playlistId: String?
        let params: String?
    }

    struct WatchPlaylistEndpoint: Codable {
        let playlistId: String
        let params: String?
    }
}

// MARK: - Search Response

struct SearchResponse: Codable {
    let contents: Contents?
    let header: Header?

    struct Contents: Codable {
        let tabbedSearchResultsRenderer: TabbedSearchResultsRenderer?
        let sectionListRenderer: SectionListRenderer?

        struct SectionListRenderer: Codable {
            let contents: [SectionContent]?

            struct SectionContent: Codable {
                let musicShelfRenderer: MusicShelfRenderer?
                let musicCardShelfRenderer: MusicCardShelfRenderer?
            }
        }

        struct TabbedSearchResultsRenderer: Codable {
            let tabs: [Tab]?

            struct Tab: Codable {
                let tabRenderer: TabRenderer?

                struct TabRenderer: Codable {
                    let content: Content?

                    struct Content: Codable {
                        let sectionListRenderer: SectionListRenderer?
                    }
                }
            }
        }
    }

    struct Header: Codable {
        let musicHeaderRenderer: MusicHeaderRenderer?

        struct MusicHeaderRenderer: Codable {
            let title: YTText?
        }
    }
}

struct MusicCardShelfRenderer: Codable {
    let title: YTText?
    let subtitle: YTText?
    let contents: [MusicShelfRenderer.Content]?
}

struct MusicShelfRenderer: Codable {
    let title: YTText?
    let contents: [Content]?
    let continuations: [Continuation]?

    struct Content: Codable {
        let musicResponsiveListItemRenderer: MusicResponsiveListItemRenderer?
    }

    struct MusicResponsiveListItemRenderer: Codable {
        let flexColumns: [FlexColumn]?
        let fixedColumns: [FlexColumn]?
        let thumbnail: ThumbnailRenderer?
        let overlay: Overlay?
        let playlistItemData: PlaylistItemData?
        let navigationEndpoint: NavigationEndpoint?
        let badges: [Badge]?
        let menu: Menu?

        struct FlexColumn: Codable {
            let musicResponsiveListItemFlexColumnRenderer: MusicResponsiveListItemFlexColumnRenderer?

            struct MusicResponsiveListItemFlexColumnRenderer: Codable {
                let text: YTText?
            }
        }

        struct ThumbnailRenderer: Codable {
            let musicThumbnailRenderer: MusicThumbnailRenderer?

            struct MusicThumbnailRenderer: Codable {
                let thumbnail: ThumbnailList?

                struct ThumbnailList: Codable {
                    let thumbnails: [Thumbnail]?
                }
            }
        }

        struct Overlay: Codable {
            let musicItemThumbnailOverlayRenderer: MusicItemThumbnailOverlayRenderer?

            struct MusicItemThumbnailOverlayRenderer: Codable {
                let content: Content?

                struct Content: Codable {
                    let musicPlayButtonRenderer: MusicPlayButtonRenderer?

                    struct MusicPlayButtonRenderer: Codable {
                        let playNavigationEndpoint: NavigationEndpoint?
                    }
                }
            }
        }

        struct PlaylistItemData: Codable {
            let videoId: String?
        }

        struct Badge: Codable {
            let musicInlineBadgeRenderer: MusicInlineBadgeRenderer?

            struct MusicInlineBadgeRenderer: Codable {
                let icon: Icon?

                struct Icon: Codable {
                    let iconType: String?
                }
            }
        }

        struct Menu: Codable {
            let menuRenderer: MenuRenderer?

            struct MenuRenderer: Codable {
                let items: [MenuItem]?

                struct MenuItem: Codable {
                    let toggleMenuServiceItemRenderer: ToggleMenuServiceItemRenderer?
                    let menuNavigationItemRenderer: MenuNavigationItemRenderer?

                    struct ToggleMenuServiceItemRenderer: Codable {
                        let defaultIcon: Icon?

                        struct Icon: Codable {
                            let iconType: String?
                        }
                    }

                    struct MenuNavigationItemRenderer: Codable {
                        let icon: Icon?
                        let navigationEndpoint: NavigationEndpoint?

                        struct Icon: Codable {
                            let iconType: String?
                        }
                    }
                }
            }
        }
    }

    struct Continuation: Codable {
        let nextContinuationData: NextContinuationData?

        struct NextContinuationData: Codable {
            let continuation: String
        }
    }
}

// MARK: - Player Response

struct PlayerResponse: Codable {
    let videoDetails: VideoDetails?
    let streamingData: StreamingData?
    let playabilityStatus: PlayabilityStatus?
    let assets: Assets?

    struct VideoDetails: Codable {
        // videoId/title opcionales: respuestas de error (TV bot-check) los omiten y
        // antes rompían el decode entero (keyNotFound title) en vez de llegar al
        // playabilityStatus.
        let videoId: String?
        let title: String?
        let lengthSeconds: String?
        let channelId: String?
        let author: String?
        let thumbnail: ThumbnailList?

        struct ThumbnailList: Codable {
            let thumbnails: [Thumbnail]?
        }
    }

    struct StreamingData: Codable {
        let expiresInSeconds: String?
        let formats: [Format]?
        let adaptiveFormats: [Format]?

        struct Format: Codable {
            let itag: Int
            let url: String?
            let mimeType: String
            let bitrate: Int?
            let width: Int?
            let height: Int?
            let contentLength: String?
            let quality: String?
            let qualityLabel: String?
            let audioQuality: String?
            let audioSampleRate: String?
            let audioChannels: Int?
            let loudnessDb: Double?
            let signatureCipher: String?
            let cipher: String?
        }
    }

    struct PlayabilityStatus: Codable {
        let status: String
        let reason: String?
    }

    struct Assets: Codable {
        let js: String?
    }
}

// MARK: - Browse Response

struct BrowseResponse: Codable {
    let contents: Contents?
    let header: Header?
    let continuationContents: ContinuationContents?
    let onResponseReceivedActions: [OnResponseReceivedAction]?

    struct OnResponseReceivedAction: Codable {
        let appendContinuationItemsAction: AppendContinuationItemsAction?

        struct AppendContinuationItemsAction: Codable {
            let continuationItems: [MusicPlaylistShelfRenderer.Content]?
        }
    }

    struct ContinuationContents: Codable {
        let sectionListContinuation: SectionListContinuation?
        let musicPlaylistShelfContinuation: MusicPlaylistShelfContinuation?

        struct MusicPlaylistShelfContinuation: Codable {
            let contents: [MusicPlaylistShelfRenderer.Content]?
            let continuations: [Continuation]?

            struct Continuation: Codable {
                let nextContinuationData: NextContinuationData?

                struct NextContinuationData: Codable {
                    let continuation: String
                }
            }
        }

        struct SectionListContinuation: Codable {
            let contents: [SectionContent]?
            let continuations: [Continuation]?

            struct SectionContent: Codable {
                let musicCarouselShelfRenderer: MusicCarouselShelfRenderer?
                let musicShelfRenderer: MusicShelfRenderer?
                let musicPlaylistShelfRenderer: MusicPlaylistShelfRenderer?
            }

            struct Continuation: Codable {
                let nextContinuationData: NextContinuationData?

                struct NextContinuationData: Codable {
                    let continuation: String
                }
            }
        }
    }

    struct Contents: Codable {
        let singleColumnBrowseResultsRenderer: SingleColumnBrowseResultsRenderer?
        let twoColumnBrowseResultsRenderer: TwoColumnBrowseResultsRenderer?
        let sectionListRenderer: SectionListRenderer?

        struct TwoColumnBrowseResultsRenderer: Codable {
            let tabs: [Tab]?
            let secondaryContents: SecondaryContents?
            
            struct Tab: Codable {
                let tabRenderer: TabRenderer?
                
                struct TabRenderer: Codable {
                    let content: Content?
                    
                    struct Content: Codable {
                        let sectionListRenderer: SectionListRenderer?
                    }
                }
            }
            
            struct SecondaryContents: Codable {
                let sectionListRenderer: SectionListRenderer?
            }
        }

        struct SingleColumnBrowseResultsRenderer: Codable {
            let tabs: [Tab]?

            struct Tab: Codable {
                let tabRenderer: TabRenderer?

                struct TabRenderer: Codable {
                    let content: Content?

                    struct Content: Codable {
                        let sectionListRenderer: SectionListRenderer?
                    }
                }
            }
        }

        struct SectionListRenderer: Codable {
            let header: Header?
            let contents: [SectionContent]?
            let continuations: [Continuation]?

            struct Header: Codable {
                let chipCloudRenderer: ChipCloudRenderer?

                struct ChipCloudRenderer: Codable {
                    let chips: [Chip]?

                    struct Chip: Codable {
                        let chipCloudChipRenderer: ChipCloudChipRenderer?

                        struct ChipCloudChipRenderer: Codable {
                            let text: YTText?
                            let navigationEndpoint: NavigationEndpoint?
                            let isSelected: Bool?
                        }
                    }
                }
            }

            struct SectionContent: Codable {
                let musicCarouselShelfRenderer: MusicCarouselShelfRenderer?
                let musicShelfRenderer: MusicShelfRenderer?
                let musicPlaylistShelfRenderer: MusicPlaylistShelfRenderer?
                let musicResponsiveHeaderRenderer: MusicResponsiveHeaderRenderer?
                let gridRenderer: GridRenderer?
                let itemSectionRenderer: ItemSectionRenderer?
            }

            struct ItemSectionRenderer: Codable {
                let contents: [ItemSectionContent]?

                struct ItemSectionContent: Codable {
                    let messageRenderer: MessageRenderer?

                    struct MessageRenderer: Codable {
                        let text: YTText?
                        let button: Button?

                        struct Button: Codable {
                            let buttonRenderer: ButtonRenderer?

                            struct ButtonRenderer: Codable {
                                let text: YTText?
                                let navigationEndpoint: NavigationEndpoint?

                                struct NavigationEndpoint: Codable {
                                    let signInEndpoint: SignInEndpoint?

                                    struct SignInEndpoint: Codable {
                                        let hack: Bool?
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            struct MusicResponsiveHeaderRenderer: Codable {
                let title: YTText?
                let subtitle: YTText?
                let straplineTextOne: YTText?
                let thumbnail: ThumbnailWrapper?
                
                struct ThumbnailWrapper: Codable {
                    let musicThumbnailRenderer: MusicThumbnailRenderer?
                    
                    struct MusicThumbnailRenderer: Codable {
                        let thumbnail: ThumbnailList?
                        
                        struct ThumbnailList: Codable {
                            let thumbnails: [Thumbnail]?
                        }
                    }
                }
            }

            struct Continuation: Codable {
                let nextContinuationData: NextContinuationData?

                struct NextContinuationData: Codable {
                    let continuation: String
                }
            }
        }
    }

    struct Header: Codable {
        let musicDetailHeaderRenderer: MusicDetailHeaderRenderer?
        let musicEditablePlaylistDetailHeaderRenderer: MusicEditablePlaylistDetailHeaderRenderer?
        let musicImmersiveHeaderRenderer: MusicImmersiveHeaderRenderer?
        let musicVisualHeaderRenderer: MusicVisualHeaderRenderer?

        struct MusicDetailHeaderRenderer: Codable {
            let title: YTText?
            let subtitle: YTText?
            let description: YTText?
            let thumbnail: ThumbnailRenderer?
            let menu: Menu?

            struct ThumbnailRenderer: Codable {
                let croppedSquareThumbnailRenderer: CroppedSquareThumbnailRenderer?
                let musicThumbnailRenderer: MusicThumbnailRenderer?

                struct CroppedSquareThumbnailRenderer: Codable {
                    let thumbnail: ThumbnailList?

                    struct ThumbnailList: Codable {
                        let thumbnails: [Thumbnail]?
                    }
                }

                struct MusicThumbnailRenderer: Codable {
                    let thumbnail: ThumbnailList?

                    struct ThumbnailList: Codable {
                        let thumbnails: [Thumbnail]?
                    }
                }
            }

            struct Menu: Codable {
                let menuRenderer: MenuRenderer?

                struct MenuRenderer: Codable {
                    let topLevelButtons: [TopLevelButton]?

                    struct TopLevelButton: Codable {
                        let buttonRenderer: ButtonRenderer?

                        struct ButtonRenderer: Codable {
                            let navigationEndpoint: NavigationEndpoint?
                        }
                    }
                }
            }
        }

        struct MusicEditablePlaylistDetailHeaderRenderer: Codable {
            let header: Header?

            struct Header: Codable {
                let musicDetailHeaderRenderer: MusicDetailHeaderRenderer?
            }
        }

        struct MusicImmersiveHeaderRenderer: Codable {
            let title: YTText?
            let description: YTText?
            let thumbnail: ThumbnailRenderer?
            let playButton: PlayButton?
            let startRadioButton: StartRadioButton?
            let subscriptionButton: SubscriptionButton?

            struct ThumbnailRenderer: Codable {
                let musicThumbnailRenderer: MusicThumbnailRenderer?

                struct MusicThumbnailRenderer: Codable {
                    let thumbnail: ThumbnailList?

                    struct ThumbnailList: Codable {
                        let thumbnails: [Thumbnail]?
                    }
                }
            }

            struct PlayButton: Codable {
                let buttonRenderer: ButtonRenderer?

                struct ButtonRenderer: Codable {
                    let navigationEndpoint: NavigationEndpoint?
                }
            }

            struct StartRadioButton: Codable {
                let buttonRenderer: ButtonRenderer?

                struct ButtonRenderer: Codable {
                    let navigationEndpoint: NavigationEndpoint?
                }
            }

            struct SubscriptionButton: Codable {
                let subscribeButtonRenderer: SubscribeButtonRenderer?

                struct SubscribeButtonRenderer: Codable {
                    let channelId: String?
                }
            }
        }

        struct MusicVisualHeaderRenderer: Codable {
            let title: YTText?
            let foregroundThumbnail: ForegroundThumbnail?

            struct ForegroundThumbnail: Codable {
                let musicThumbnailRenderer: MusicThumbnailRenderer?

                struct MusicThumbnailRenderer: Codable {
                    let thumbnail: ThumbnailList?

                    struct ThumbnailList: Codable {
                        let thumbnails: [Thumbnail]?
                    }
                }
            }
        }
    }
}

struct MusicCarouselShelfRenderer: Codable {
    let header: Header?
    let contents: [Content]?

    struct Header: Codable {
        let musicCarouselShelfBasicHeaderRenderer: MusicCarouselShelfBasicHeaderRenderer?

        struct MusicCarouselShelfBasicHeaderRenderer: Codable {
            let title: YTText?
            let strapline: YTText?
            let thumbnail: ThumbnailRenderer?
            let moreContentButton: MoreContentButton?

            struct ThumbnailRenderer: Codable {
                let musicThumbnailRenderer: MusicThumbnailRenderer?

                struct MusicThumbnailRenderer: Codable {
                    let thumbnail: ThumbnailList?

                    struct ThumbnailList: Codable {
                        let thumbnails: [Thumbnail]?
                    }
                }
            }

            struct MoreContentButton: Codable {
                let buttonRenderer: ButtonRenderer?

                struct ButtonRenderer: Codable {
                    let navigationEndpoint: NavigationEndpoint?
                }
            }
        }
    }

    struct Content: Codable {
        let musicTwoRowItemRenderer: MusicTwoRowItemRenderer?
        let musicNavigationButtonRenderer: MusicNavigationButtonRenderer?
        // Top artists y otros carousels traen listItems directos (verificado charts)
        let musicResponsiveListItemRenderer: MusicShelfRenderer.MusicResponsiveListItemRenderer?

        struct MusicTwoRowItemRenderer: Codable {
            let title: YTText?
            let subtitle: YTText?
            let navigationEndpoint: NavigationEndpoint?
            let thumbnailRenderer: ThumbnailRenderer?
            let thumbnailOverlay: ThumbnailOverlay?
            let menu: Menu?

            struct ThumbnailRenderer: Codable {
                let musicThumbnailRenderer: MusicThumbnailRenderer?

                struct MusicThumbnailRenderer: Codable {
                    let thumbnail: ThumbnailList?

                    struct ThumbnailList: Codable {
                        let thumbnails: [Thumbnail]?
                    }
                }
            }

            struct ThumbnailOverlay: Codable {
                let musicItemThumbnailOverlayRenderer: MusicItemThumbnailOverlayRenderer?

                struct MusicItemThumbnailOverlayRenderer: Codable {
                    let content: Content?

                    struct Content: Codable {
                        let musicPlayButtonRenderer: MusicPlayButtonRenderer?

                        struct MusicPlayButtonRenderer: Codable {
                            let playNavigationEndpoint: NavigationEndpoint?
                        }
                    }
                }
            }

            struct Menu: Codable {
                let menuRenderer: MenuRenderer?

                struct MenuRenderer: Codable {
                    let items: [MenuItem]?

                    struct MenuItem: Codable {
                        let menuNavigationItemRenderer: MenuNavigationItemRenderer?

                        struct MenuNavigationItemRenderer: Codable {
                            let icon: Icon?
                            let navigationEndpoint: NavigationEndpoint?

                            struct Icon: Codable {
                                let iconType: String?
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MusicPlaylistShelfRenderer: Codable {
    let playlistId: String?
    let contents: [Content]?
    let continuations: [Continuation]?

    struct Content: Codable {
        let musicResponsiveListItemRenderer: MusicShelfRenderer.MusicResponsiveListItemRenderer?
        let continuationItemRenderer: ContinuationItemRenderer?

        struct ContinuationItemRenderer: Codable {
            let continuationEndpoint: ContinuationEndpoint?

            struct ContinuationEndpoint: Codable {
                let continuationCommand: ContinuationCommand?

                struct ContinuationCommand: Codable {
                    let token: String?
                }
            }
        }
    }

    struct Continuation: Codable {
        let nextContinuationData: NextContinuationData?

        struct NextContinuationData: Codable {
            let continuation: String
        }
    }
}

// MARK: - Next Response (Queue)

struct NextResponse: Codable {
    let contents: Contents?
    let currentVideoEndpoint: CurrentVideoEndpoint?

    struct Contents: Codable {
        let singleColumnMusicWatchNextResultsRenderer: SingleColumnMusicWatchNextResultsRenderer?

        struct SingleColumnMusicWatchNextResultsRenderer: Codable {
            let tabbedRenderer: TabbedRenderer?

            struct TabbedRenderer: Codable {
                let watchNextTabbedResultsRenderer: WatchNextTabbedResultsRenderer?

                struct WatchNextTabbedResultsRenderer: Codable {
                    let tabs: [Tab]?

                    struct Tab: Codable {
                        let tabRenderer: TabRenderer?

                        struct TabRenderer: Codable {
                            let content: Content?

                            struct Content: Codable {
                                let musicQueueRenderer: MusicQueueRenderer?

                                struct MusicQueueRenderer: Codable {
                                    let content: QueueContent?

                                    struct QueueContent: Codable {
                                        let playlistPanelRenderer: PlaylistPanelRenderer?

                                        struct PlaylistPanelRenderer: Codable {
                                            let contents: [PlaylistPanelVideoRenderer]?
                                            let continuations: [Continuation]?

                                            struct PlaylistPanelVideoRenderer: Codable {
                                                let playlistPanelVideoRenderer: VideoRenderer?

                                                struct VideoRenderer: Codable {
                                                    let videoId: String?
                                                    let title: YTText?
                                                    let longBylineText: YTText?
                                                    let thumbnail: ThumbnailList?

                                                    struct ThumbnailList: Codable {
                                                        let thumbnails: [Thumbnail]?
                                                    }
                                                }
                                            }

                                            struct Continuation: Codable {
                                                let nextContinuationData: NextContinuationData?

                                                struct NextContinuationData: Codable {
                                                    let continuation: String
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    struct CurrentVideoEndpoint: Codable {
        let watchEndpoint: NavigationEndpoint.WatchEndpoint?
    }
}

// MARK: - Music Navigation Button (for Mood & Genres)

struct MusicNavigationButtonRenderer: Codable {
    let buttonText: YTText?
    let solid: SolidBackground?
    let clickCommand: NavigationEndpoint?

    struct SolidBackground: Codable {
        let leftStripeColor: Int64?
    }
}

// MARK: - Grid Renderer (for Explore/Browse pages)

struct GridRenderer: Codable {
    let items: [Item]?
    let header: Header?

    struct Header: Codable {
        let gridHeaderRenderer: GridHeaderRenderer?

        struct GridHeaderRenderer: Codable {
            let title: YTText?
        }
    }

    struct Item: Codable {
        let musicTwoRowItemRenderer: MusicCarouselShelfRenderer.Content.MusicTwoRowItemRenderer?
        let musicNavigationButtonRenderer: MusicNavigationButtonRenderer?
    }
}
