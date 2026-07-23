# Архитектура Orbit

## Границы продукта

Orbit — `LSUIElement`-приложение без Dock-иконки. Production UI состоит из одного
`NSStatusItem` и одного переиспользуемого окна настроек. Отображение Spaces не
требует сети или сторонних зависимостей.

macOS не предоставляет публичного API полного порядка Spaces. Основной reader
динамически разрешает private WindowServer symbols, а plist `com.apple.spaces`
использует как fallback. Это осознанный риск direct-distribution приложения и
главная точка проверки для каждой новой major-версии macOS.

## Владение и жизненный цикл

```text
OrbitApp
└─ AppDelegate
   ├─ AppSettings
   ├─ SpaceViewModel
   │  ├─ SystemSpacesReader
   │  └─ SystemSpaceController
   └─ StatusBarController
      ├─ NSStatusItem + bitmap renderer
      ├─ paused-when-idle CADisplayLink
      └─ SettingsWindowController (создаётся по требованию)
```

- `AppDelegate` создаёт долгоживущие модели после запуска приложения.
- `SpaceViewModel.start()` запускает reader; `stop()` отменяет refresh и polling.
- `StatusBarController.stop()` инвалидирует display link, подписки и status item.
- Settings controller хранит одно окно. Интерактивное превью существует только
  пока окно показано; при закрытии его display link и event monitors dismantle-ятся.

Все изменяемые UI-модели изолированы `@MainActor`. Фоновые WindowServer/plist reads
выполняются вне main actor, а публикация snapshot возвращается на main actor.

## Поток Spaces

1. `NSWorkspace.activeSpaceDidChangeNotification` сообщает активную смену.
2. Полусекундный single-flight watchdog замечает изменения структуры Mission
   Control, включая появление и исчезновение fullscreen Spaces.
3. `SpaceViewModel` отвергает transient snapshot без Current Space и устаревшие
   результаты отменённых refresh-запросов.
4. `StatusBarController` получает только изменившиеся published-значения и запускает
   display link лишь на время перехода, hover или визуального refresh.

## Настройки и persistence

`AppSettings` владеет ключами `UserDefaults`, их нормализацией и сохранением. Смена
порядка Spaces не меняет индивидуальные color slots: идентичность хранится по
desktop identifier. Существующие ключи и raw values считаются частью формата данных;
их изменение требует миграции и теста восстановления.

## Motion и accessibility

Status item и Settings preview используют общие motion/renderer primitives.
`CADisplayLink` запрашивает диапазон 60–120 Гц, но при отсутствии движения paused.
`Reduce Motion` прекращает пространственные переходы и сохраняет конечное состояние.
Системные `Increase Contrast` и `Reduce Transparency` обрабатываются в presentation
слое, не меняя пользовательские цвета.

## Совместимость

| Среда | Уровень подтверждения |
| --- | --- |
| macOS 14 | deployment target и статическая availability; нужен runtime smoke test |
| macOS 15 arm64 | сборка и автоматические тесты проверены локально |
| macOS 26 | SDK build; нужен runtime test WindowServer/fullscreen/TCC |
| macOS 27 | не подтверждена; обязательна отдельная проверка private symbols/schema |
| Intel | universal Release build; нужен реальный runtime smoke test |

Новый публичный API допускается только с availability fallback до macOS 14. API
macOS 27-only не используются. Поддержка новой macOS не считается подтверждённой
только потому, что проект собрался новым SDK.

## Release checklist

1. Собрать Debug и Release явным Xcode toolchain через `DEVELOPER_DIR`.
2. Запустить весь `OrbitTests` target без удаления или ослабления тестов.
3. Проверить light/dark, Reduce Motion/Transparency, Increase Contrast и обе
   локализации.
4. Проверить 1, 2, 6, 12+ Spaces, fullscreen и multiple displays.
5. Проверить fresh/allowed/denied состояния Accessibility и Automation.
6. Снять idle Activity Monitor/Time Profiler trace и убедиться, что display links
   paused, а Settings preview отсутствует после закрытия окна.
7. Для распространения отдельно выполнить Developer ID signing и notarization.
