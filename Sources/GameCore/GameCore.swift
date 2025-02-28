import ActiveGamesFeature
import AudioPlayerClient
import BottomMenu
import ClientModels
import ComposableArchitecture
import ComposableGameCenter
import CubeCore
import DictionaryClient
import GameOverFeature
import HapticsCore
import LowPowerModeClient
import Overture
import SharedModels
import SwiftUI
import Tagged
import TcaHelpers
import UpgradeInterstitialFeature

public struct Game: ReducerProtocol {
  public struct State: Equatable {
    public var activeGames: ActiveGamesState
    public var alert: AlertState<AlertAction>?
    public var bottomMenu: BottomMenuState<Action>?
    public var cubes: Puzzle
    public var cubeStartedShakingAt: Date?
    public var gameContext: ClientModels.GameContext
    public var gameCurrentTime: Date
    public var gameMode: GameMode
    public var gameOver: GameOver.State?
    public var gameStartTime: Date
    public var isDemo: Bool
    public var isGameLoaded: Bool
    public var isOnLowPowerMode: Bool
    public var isPanning: Bool
    public var isSettingsPresented: Bool
    public var isTrayVisible: Bool
    public var language: Language
    public var moves: Moves
    public var optimisticallySelectedFace: IndexedCubeFace?
    public var secondsPlayed: Int
    public var selectedWord: [IndexedCubeFace]
    public var selectedWordIsValid: Bool
    public var upgradeInterstitial: UpgradeInterstitial.State?
    public var wordSubmitButton: WordSubmitButtonFeature.ButtonState

    public init(
      activeGames: ActiveGamesState = .init(),
      alert: AlertState<AlertAction>? = nil,
      bottomMenu: BottomMenuState<Action>? = nil,
      cubes: Puzzle,
      cubeStartedShakingAt: Date? = nil,
      gameContext: ClientModels.GameContext,
      gameCurrentTime: Date,
      gameMode: GameMode,
      gameOver: GameOver.State? = nil,
      gameStartTime: Date,
      isDemo: Bool = false,
      isGameLoaded: Bool = false,
      isPanning: Bool = false,
      isOnLowPowerMode: Bool = false,
      isSettingsPresented: Bool = false,
      isTrayVisible: Bool = false,
      language: Language = .en,
      moves: Moves = [],
      optimisticallySelectedFace: IndexedCubeFace? = nil,
      secondsPlayed: Int = 0,
      selectedWord: [IndexedCubeFace] = [],
      selectedWordIsValid: Bool = false,
      upgradeInterstitial: UpgradeInterstitial.State? = nil,
      wordSubmit: WordSubmitButtonFeature.ButtonState = .init()
    ) {
      self.activeGames = activeGames
      self.alert = alert
      self.bottomMenu = bottomMenu
      self.cubes = cubes
      self.cubeStartedShakingAt = cubeStartedShakingAt
      self.gameContext = gameContext
      self.gameCurrentTime = gameCurrentTime
      self.gameMode = gameMode
      self.gameOver = gameOver
      self.gameStartTime = gameStartTime
      self.isDemo = isDemo
      self.isGameLoaded = isGameLoaded
      self.isOnLowPowerMode = isOnLowPowerMode
      self.isPanning = isPanning
      self.isSettingsPresented = isSettingsPresented
      self.isTrayVisible = isTrayVisible
      self.language = language
      self.moves = moves
      self.optimisticallySelectedFace = optimisticallySelectedFace
      self.secondsPlayed = secondsPlayed
      self.selectedWord = selectedWord
      self.selectedWordIsValid = selectedWordIsValid
      self.upgradeInterstitial = upgradeInterstitial
      self.wordSubmitButton = wordSubmit
    }

    public var dailyChallengeId: DailyChallenge.Id? {
      guard case let .dailyChallenge(id) = self.gameContext else { return nil }
      return id
    }

    public var isNavVisible: Bool {
      !self.isDemo
    }

    public var isTrayAvailable: Bool {
      self.gameMode != .timed && !self.activeGames.isEmpty
    }

    public var turnBasedContext: TurnBasedContext? {
      get {
        guard case let .turnBased(context) = self.gameContext else { return nil }
        return context
      }
      set {
        guard let newValue = newValue else { return }
        self.gameContext = .turnBased(newValue)
      }
    }

    public var wordSubmitButtonFeature: WordSubmitButtonFeature.State {
      get {
        .init(
          isSelectedWordValid: self.selectedWordIsValid,
          isTurnBasedMatch: self.turnBasedContext != nil,
          isYourTurn: self.turnBasedContext?.currentParticipantIsLocalPlayer ?? true,
          wordSubmitButton: self.wordSubmitButton
        )
      }
      set {
        self.wordSubmitButton = newValue.wordSubmitButton
      }
    }
  }

  public enum Action: Equatable {
    case activeGames(ActiveGamesAction)
    case alert(AlertAction)
    case cancelButtonTapped
    case confirmRemoveCube(LatticePoint)
    case delayedShowUpgradeInterstitial
    case dismissBottomMenu
    case doubleTap(index: LatticePoint)
    case endGameButtonTapped
    case exitButtonTapped
    case forfeitGameButtonTapped
    case gameCenter(GameCenterAction)
    case gameLoaded
    case gameOver(GameOver.Action)
    case lowPowerModeChanged(Bool)
    case matchesLoaded(TaskResult<[TurnBasedMatch]>)
    case menuButtonTapped
    case task
    case pan(UIGestureRecognizer.State, PanData?)
    case savedGamesLoaded(TaskResult<SavedGamesState>)
    case settingsButtonTapped
    case submitButtonTapped(reaction: Move.Reaction?)
    case tap(UIGestureRecognizer.State, IndexedCubeFace?)
    case timerTick(Date)
    case trayButtonTapped
    case upgradeInterstitial(UpgradeInterstitial.Action)
    case wordSubmitButton(WordSubmitButtonFeature.Action)
  }

  public enum AlertAction: Equatable {
    case dismiss
    case dontForfeitButtonTapped
    case forfeitButtonTapped
  }

  public enum GameCenterAction: Equatable {
    case listener(LocalPlayerClient.ListenerEvent)
    case turnBasedMatchResponse(TaskResult<TurnBasedMatch>)
  }

  @Dependency(\.audioPlayer) var audioPlayer
  @Dependency(\.apiClient.currentPlayer) var currentPlayer
  @Dependency(\.dictionary.contains) var dictionaryContains
  @Dependency(\.gameCenter) var gameCenter
  @Dependency(\.lowPowerMode) var lowPowerMode
  @Dependency(\.mainQueue) var mainQueue
  @Dependency(\.mainRunLoop) var mainRunLoop
  @Dependency(\.serverConfig.config) var serverConfig
  @Dependency(\.userDefaults) var userDefaults

  public init() {}

  func date() -> Date { self.mainRunLoop.now.date }

  public var body: some ReducerProtocol<State, Action> {
    self.core
      .onChange(of: \.selectedWord) { selectedWord, state, _ in
        state.selectedWordIsValid =
          !state.selectedWordHasAlreadyBeenPlayed
          && self.dictionaryContains(state.selectedWordString, state.language)
        return .none
      }
      .filterActionsForYourTurn()
      .ifLet(\.gameOver, action: /Action.gameOver) {
        GameOver()
      }
      .ifLet(\.upgradeInterstitial, action: /Action.upgradeInterstitial) {
        UpgradeInterstitial()
      }
      .sounds()
  }

  @ReducerBuilder<State, Action>
  var core: some ReducerProtocol<State, Action> {
    Reduce { state, action in
      switch action {
      case .activeGames:
        return .none

      case .alert(.dismiss), .alert(.dontForfeitButtonTapped):
        state.alert = nil
        return .none

      case .alert(.forfeitButtonTapped):
        state.alert = nil

        guard let match = state.turnBasedContext?.match
        else { return .none }

        return .fireAndForget {
          let localPlayer = self.gameCenter.localPlayer.localPlayer()
          let currentParticipantIsLocalPlayer =
            match.currentParticipant?.player?.gamePlayerId == localPlayer.gamePlayerId

          if currentParticipantIsLocalPlayer {
            try await self.gameCenter.turnBasedMatch.endMatchInTurn(
              .init(
                for: match.matchId,
                matchData: match.matchData ?? Data(),
                localPlayerId: localPlayer.gamePlayerId,
                localPlayerMatchOutcome: .quit,
                message: "\(localPlayer.displayName) forfeited the match."
              )
            )
          } else {
            try await self.gameCenter.turnBasedMatch
              .participantQuitOutOfTurn(match.matchId)
          }
        }

      case .cancelButtonTapped:
        state.selectedWord = []
        return .none

      case let .confirmRemoveCube(index):
        state.bottomMenu = nil
        state.removeCube(at: index, playedAt: self.date())
        state.selectedWord = []
        return .none

      case .delayedShowUpgradeInterstitial:
        state.upgradeInterstitial = .init()
        return .none

      case .dismissBottomMenu:
        state.bottomMenu = nil
        return .none

      case let .doubleTap(index):
        guard state.selectedWord.count <= 1
        else { return .none }

        return state.tryToRemoveCube(at: index)

      case .endGameButtonTapped:
        return .none

      case .exitButtonTapped:
        return .none

      case .forfeitGameButtonTapped:
        state.alert = .init(
          title: .init("Are you sure?"),
          message: .init(
            """
            Forfeiting will end the game and your opponent will win. Are you sure you want to \
            forfeit?
            """
          ),
          primaryButton: .default(.init("Don’t forfeit"), action: .send(.dontForfeitButtonTapped)),
          secondaryButton: .destructive(.init("Yes, forfeit"), action: .send(.forfeitButtonTapped))
        )
        return .none

      case .gameCenter:
        return .none

      case .gameLoaded:
        state.isGameLoaded = true
        return .run { send in
          for await instant in self.mainRunLoop.timer(interval: .seconds(1)) {
            await send(.timerTick(instant.date))
          }
        }

      case .gameOver(.delegate(.close)):
        return .none

      case let .gameOver(.delegate(.startGame(inProgressGame))):
        state = .init(inProgressGame: inProgressGame)
        return .none

      case .gameOver:
        return .none

      case let .lowPowerModeChanged(isOn):
        state.isOnLowPowerMode = isOn
        return .none

      case .matchesLoaded:
        return .none

      case .menuButtonTapped:
        state.bottomMenu = .gameMenu(state: state)
        return .none

      case .task:
        guard !state.isGameOver else { return .none }
        state.gameCurrentTime = self.date()

        return .run { [gameContext = state.gameContext] send in
          await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
              for await isLowPower in await self.lowPowerMode.start() {
                await send(.lowPowerModeChanged(isLowPower))
              }
            }

            if gameContext.isTurnBased {
              group.addTask {
                let playedGamesCount = await self.userDefaults
                  .incrementMultiplayerOpensCount()
                let isFullGamePurchased = self.currentPlayer()?.appleReceipt != nil
                guard
                  !isFullGamePurchased,
                  shouldShowInterstitial(
                    gamePlayedCount: playedGamesCount,
                    gameContext: .init(gameContext: gameContext),
                    serverConfig: self.serverConfig()
                  )
                else { return }
                try await self.mainRunLoop.sleep(for: .seconds(3))
                await send(.delayedShowUpgradeInterstitial, animation: .default)
              }
            }

            group.addTask {
              try await self.mainQueue.sleep(for: 0.5)
              await send(.gameLoaded)
            }
          }
          for music in AudioPlayerClient.Sound.allMusic {
            await self.audioPlayer.stop(music)
          }
        }

      case .pan(.began, _):
        state.isPanning = true
        return .none

      case let .pan(.changed, .some(panData)):
        guard panData.normalizedPoint.isAwayFromCorners else { return .none }

        if let lastLetter = state.selectedWord.last,
          !lastLetter.isTouching(panData.cubeFaceState),
          !state.selectedWord.contains(panData.cubeFaceState)
        {
          return .none
        }

        if let index = state.selectedWord.firstIndex(of: panData.cubeFaceState) {
          state.selectedWord.removeSubrange((index + 1)...)
          return .none
        } else if state.cubes.isPlayable(
          side: panData.cubeFaceState.side, index: panData.cubeFaceState.index)
        {
          state.selectedWord.append(panData.cubeFaceState)
          return .none
        }

        return .none

      case .pan(.cancelled, _), .pan(.ended, .none), .pan(.failed, _):
        state.isPanning = false
        state.selectedWord = []
        return .none

      case .pan:
        state.isPanning = false
        return .none

      case .savedGamesLoaded:
        return .none

      case .settingsButtonTapped:
        state.isSettingsPresented = true
        return .none

      case let .submitButtonTapped(reaction: reaction),
        let .wordSubmitButton(.delegate(.confirmSubmit(reaction: reaction))):

        let move = Move(
          playedAt: self.mainRunLoop.now.date,
          playerIndex: state.turnBasedContext?.localPlayerIndex,
          reactions: zip(state.turnBasedContext?.localPlayerIndex, reaction)
            .map { [$0: $1] },
          score: state.selectedWordScore,
          type: .playedWord(state.selectedWord)
        )

        let result = verify(
          move: move,
          on: &state.cubes,
          isValidWord: { self.dictionaryContains($0, state.language) },
          previousMoves: state.moves
        )

        defer { state.selectedWord = [] }

        guard result != nil else { return .none }

        state.moves.append(move)

        return .fireAndForget { [state] in
          await withThrowingTaskGroup(of: Void.self) { group in
            for face in state.selectedWord where !state.cubes[face.index].isInPlay {
              group.addTask {
                try await self.mainQueue
                  .sleep(for: .milliseconds(removeCubeDelay(index: face.index)))
                await self.audioPlayer.play(.cubeRemove)
              }
            }
          }
        }

      case let .tap(.began, face):
        state.optimisticallySelectedFace = nil

        // If tapping off the cube, deselect everything
        guard
          let face = face,
          state.cubes.isPlayable(side: face.side, index: face.index)
        else {
          state.selectedWord = []
          return .none
        }

        // If tapping on a previously selected face then we may back up to that selected face
        if let index = state.selectedWord.firstIndex(of: face) {
          // If not tapping on the last selected face then optimistically back up the selection to that face
          if index != state.selectedWord.endIndex - 1 {
            state.optimisticallySelectedFace = face
            state.selectedWord.removeSubrange((index + 1)...)
          }
        } else {
          // If tapping on a face not connected to the previously selected face, deselect everything
          if let lastLetter = state.selectedWord.last,
            !lastLetter.isTouching(face)
          {
            state.selectedWord = []
          } else {
            state.optimisticallySelectedFace = face
            state.selectedWord.append(face)
          }
        }

        return .none

      case let .tap(.ended, face):
        defer { state.optimisticallySelectedFace = nil }

        guard
          !state.isPanning,
          let face = face,
          face != state.optimisticallySelectedFace,
          state.cubes.isPlayable(side: face.side, index: face.index)
        else {
          return .none
        }

        if let index = state.selectedWord.firstIndex(of: face) {
          // If not tapping on the last selected face then optimistically back up the selection to that face
          state.selectedWord.removeSubrange(index...)
        } else {
          state.selectedWord = []
        }

        return .none

      case .tap(.cancelled, _),
        .tap(.failed, _):
        state.optimisticallySelectedFace = nil
        return .none

      case .tap:
        return .none

      case let .timerTick(time):
        state.gameCurrentTime = time
        if state.isYourTurn && !state.isGameOver {
          state.secondsPlayed += 1
        }
        return .none

      case .trayButtonTapped:
        return .none

      case .upgradeInterstitial(.delegate(.close)),
        .upgradeInterstitial(.delegate(.fullGamePurchased)):
        state.upgradeInterstitial = nil
        return .none

      case .upgradeInterstitial:
        return .none

      case .wordSubmitButton:
        return .none
      }
    }
    Scope(state: \.wordSubmitButtonFeature, action: /Action.wordSubmitButton) {
      WordSubmitButtonFeature()
    }
    GameOverLogic()
    TurnBasedLogic()
    ActiveGamesTray()
  }
}

public struct IntegratedGame<StatePath: TcaHelpers.Path, Action>: ReducerProtocol
where StatePath.Value == Game.State {
  public typealias State = StatePath.Root

  let toGameState: StatePath
  let toGameAction: CasePath<Action, Game.Action>
  let isHapticsEnabled: (StatePath.Root) -> Bool

  public init(
    state toGameState: StatePath,
    action toGameAction: CasePath<Action, Game.Action>,
    isHapticsEnabled: @escaping (StatePath.Root) -> Bool
  ) {
    self.toGameState = toGameState
    self.toGameAction = toGameAction
    self.isHapticsEnabled = isHapticsEnabled
  }

  public var body: some ReducerProtocol<State, Action> {
    EmptyReducer()._ifLet(state: self.toGameState, action: self.toGameAction) {
      Game()
    }
    .haptics(
      isEnabled: self.isHapticsEnabled,
      triggerOnChangeOf: { self.toGameState.extract(from: $0)?.selectedWord }
    )
  }
}

extension Game.State {
  public var displayTitle: String {
    switch self.gameContext {
    case .dailyChallenge:
      return "Daily challenge"
    case .shared, .solo:
      return "Solo"
    case let .turnBased(context):
      return context.otherPlayer
        .flatMap { $0.displayName.isEmpty ? nil : "vs \($0.displayName)" }
        ?? "Multiplayer"
    }
  }

  public var currentScore: Int {
    self.moves.reduce(into: 0) { $0 += $1.score }
  }

  public var isDailyChallenge: Bool {
    self.dailyChallengeId != nil
  }

  public var isGameOver: Bool {
    self.gameOver != nil
  }

  public var isResumable: Bool {
    self.gameMode == .unlimited
      && !self.isGameOver
  }

  public var isSavable: Bool {
    self.isResumable
      && (/GameContext.turnBased).isNotMatching(self.gameContext)
  }

  public var playedWords: [PlayedWord] {
    self.moves
      .reduce(into: [PlayedWord]()) {
        guard case let .playedWord(word) = $1.type else { return }
        $0.append(
          .init(
            isYourWord: $1.playerIndex == self.turnBasedContext?.localPlayerIndex,
            reactions: $1.reactions,
            score: $1.score,
            word: self.cubes.string(from: word)
          )
        )
      }
  }

  public var selectedWordScore: Int {
    score(self.selectedWordString)
  }

  public var selectedWordString: String {
    self.cubes.string(from: self.selectedWord)
  }

  public var selectedWordHasAlreadyBeenPlayed: Bool {
    self.moves.contains(where: {
      guard case let .playedWord(word) = $0.type else { return false }
      return cubes.string(from: word) == self.selectedWordString
    })
  }

  mutating func tryToRemoveCube(at index: LatticePoint) -> EffectTask<Game.Action> {
    guard self.canRemoveCube else { return .none }

    // Don't show menu for timed games.
    guard self.gameMode != .timed
    else { return .task { .confirmRemoveCube(index) } }

    let isTurnEndingRemoval: Bool
    if let turnBasedMatch = self.turnBasedContext,
      let move = self.moves.last,
      case .removedCube = move.type,
      move.playerIndex == turnBasedMatch.localPlayerIndex
    {
      isTurnEndingRemoval = true
    } else {
      isTurnEndingRemoval = false
    }

    self.bottomMenu = .removeCube(
      index: index, state: self, isTurnEndingRemoval: isTurnEndingRemoval
    )
    return .none
  }

  mutating func removeCube(at index: LatticePoint, playedAt: Date) {
    let move = Move(
      playedAt: playedAt,
      playerIndex: self.turnBasedContext?.localPlayerIndex,
      reactions: nil,
      score: 0,
      type: .removedCube(index)
    )

    let result = verify(
      move: move,
      on: &self.cubes,
      isValidWord: { _ in false },
      previousMoves: self.moves
    )

    guard result != nil
    else { return }

    self.moves.append(move)
  }

  var canRemoveCube: Bool {
    guard let turnBasedMatch = self.turnBasedContext else { return true }
    guard turnBasedMatch.currentParticipantIsLocalPlayer else { return false }
    guard let lastMove = self.moves.last else { return true }
    guard
      (/Move.MoveType.removedCube).isNotMatching(lastMove.type),
      lastMove.playerIndex != turnBasedMatch.localPlayerIndex
    else {
      return true
    }
    return lastMove.playerIndex != turnBasedMatch.localPlayerIndex
  }

  public var isYourTurn: Bool {
    guard let turnBasedMatch = self.turnBasedContext else { return true }
    guard turnBasedMatch.match.status == .open else { return false }
    guard turnBasedMatch.currentParticipantIsLocalPlayer else { return false }
    guard let lastMove = self.moves.last else { return true }
    guard lastMove.playerIndex == turnBasedMatch.localPlayerIndex else { return true }
    guard case .playedWord = lastMove.type else { return true }
    return false
  }

  public var turnBasedScores: [Move.PlayerIndex: Int] {
    Dictionary(
      grouping: self.moves
        .compactMap { move in move.playerIndex.map { (playerIndex: $0, score: move.score) } },
      by: \.playerIndex
    )
    .mapValues { $0.reduce(into: 0) { $0 += $1.score } }
  }

  public init(
    gameCurrentTime: Date,
    localPlayer: LocalPlayer,
    turnBasedMatch: TurnBasedMatch,
    turnBasedMatchData: TurnBasedMatchData
  ) {
    self.init(
      cubes: Puzzle(archivableCubes: turnBasedMatchData.cubes, moves: turnBasedMatchData.moves),
      gameContext: .turnBased(
        .init(
          localPlayer: localPlayer,
          match: turnBasedMatch,
          metadata: turnBasedMatchData.metadata
        )
      ),
      gameCurrentTime: gameCurrentTime,
      gameMode: turnBasedMatchData.gameMode,
      gameStartTime: turnBasedMatch.creationDate,
      language: turnBasedMatchData.language,
      moves: turnBasedMatchData.moves
    )
  }
}

extension TurnBasedMatchData {
  public init(
    context: TurnBasedContext,
    gameState: Game.State,
    playerId: SharedModels.Player.Id?
  ) {
    var metadata = context.metadata
    if let localPlayerIndex = context.localPlayerIndex, let playerId = playerId {
      metadata.playerIndexToId[localPlayerIndex] = playerId
    }
    self.init(
      cubes: ArchivablePuzzle(cubes: gameState.cubes),
      gameMode: gameState.gameMode,
      language: gameState.language,
      metadata: metadata,
      moves: gameState.moves
    )
  }
}

extension BottomMenuState where Action == Game.Action {
  public static func removeCube(
    index: LatticePoint,
    state: Game.State,
    isTurnEndingRemoval: Bool
  ) -> Self {
    BottomMenuState(
      title: menuTitle(state: state),
      message: isTurnEndingRemoval
        ? .init("Are you sure you want to remove this cube? This will end your turn.")
        : nil,
      footerButton: .init(
        title: isTurnEndingRemoval
          ? .init("Yes, remove cube")
          : .init("Remove cube"),
        icon: .init(systemName: "trash"),
        action: .init(action: .confirmRemoveCube(index), animation: .default)
      ),
      onDismiss: .init(action: .dismissBottomMenu, animation: .default)
    )
  }

  static func gameMenu(state: Game.State) -> Self {
    var menu = BottomMenuState(title: menuTitle(state: state))
    menu.onDismiss = .init(action: .dismissBottomMenu, animation: .default)

    if state.isResumable {
      menu.buttons.append(
        .init(
          title: .init("Main menu"),
          icon: .exit,
          action: .init(action: .exitButtonTapped, animation: .default)
        )
      )
    }

    if state.turnBasedContext != nil {
      menu.buttons.append(
        .init(
          title: .init("Forfeit"),
          icon: .flag,
          action: .init(action: .forfeitGameButtonTapped, animation: .default)
        )
      )
    } else {
      menu.buttons.append(
        .init(
          title: .init("End game"),
          icon: .flag,
          action: .init(action: .endGameButtonTapped, animation: .default)
        )
      )
    }

    menu.footerButton = .init(
      title: .init("Settings"),
      icon: Image(systemName: "gear"),
      action: .init(action: .settingsButtonTapped, animation: .default)
    )

    return menu
  }
}

extension Image {
  static let flag = Self(uiImage: UIImage(named: "flag", in: Bundle.module, with: nil)!)
  static let exit = Self(uiImage: UIImage(named: "exit", in: Bundle.module, with: nil)!)
}

func menuTitle(state: Game.State) -> TextState {
  .init(state.displayTitle)
}

extension UpgradeInterstitialFeature.GameContext {
  fileprivate init(gameContext: ClientModels.GameContext) {
    switch gameContext {
    case .dailyChallenge:
      self = .dailyChallenge
    case .shared:
      self = .shared
    case .solo:
      self = .solo
    case .turnBased:
      self = .turnBased
    }
  }
}

extension CGPoint {
  private static let threshold: CGFloat = 0.35
  private static let thresholdSquared = threshold * threshold
  var isAwayFromCorners: Bool {
    self.x * self.x + self.y * self.y <= Self.thresholdSquared
  }
}

extension CompletedGame {
  public init(gameState: Game.State) {
    self.init(
      cubes: .init(cubes: gameState.cubes),
      gameContext: gameState.gameContext.completedGameContext,
      gameMode: gameState.gameMode,
      gameStartTime: gameState.gameStartTime,
      language: gameState.language,
      localPlayerIndex: gameState.turnBasedContext?.localPlayerIndex,
      moves: gameState.moves,
      secondsPlayed: gameState.secondsPlayed
    )
  }
}

extension DependencyValues {
  public mutating func gameOnboarding() {
    let previousValues = self

    self = Self.test
    self.apiClient = .noop
    self.audioPlayer = previousValues.audioPlayer
    self.build = .noop
    self.database = .noop
    self.date = previousValues.date
    self.dictionary = previousValues.dictionary
    self.feedbackGenerator = previousValues.feedbackGenerator
    self.fileClient = .noop
    self.gameCenter = .noop
    self.mainRunLoop = previousValues.mainRunLoop
    self.mainQueue = previousValues.mainQueue
    self.remoteNotifications = .noop
    self.serverConfig = .noop
    self.storeKit = .noop
    self.userNotifications = .noop
  }
}
