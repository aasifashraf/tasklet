import 'package:flutter/material.dart';

import '../core/colors.dart';
import '../core/models.dart';

/// Design tokens (SPEC §8). Read with `Tokens.of(context)`.
@immutable
class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.raised,
    required this.border,
    required this.hover,
    required this.selected,
    required this.openHighlight,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.accent,
    required this.danger,
    required this.warning,
    required this.success,
    required this.backdrop,
  });

  final Color background;
  final Color sidebar;
  final Color surface;
  final Color raised;
  final Color border;
  final Color hover;
  final Color selected;
  final Color openHighlight;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color accent;
  final Color danger;
  final Color warning;
  final Color success;
  final Color backdrop;

  static const _accent = Color(0xFF3E7BFA);

  static const light = Tokens(
    background: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF4F4F5),
    surface: Color(0xFFFAFAFA),
    raised: Color(0xFFFFFFFF),
    border: Color(0xFFE4E4E7),
    hover: Color(0x0A000000),
    selected: Color(0x12000000),
    openHighlight: Color(0x143E7BFA),
    primary: Color(0xFF1C1C1E),
    // Contrast floors (test/ui/design_system_test.dart): secondary ≥ 4.5:1, tertiary ≥ 3:1 on every surface.
    secondary: Color(0xA61C1C1E),
    tertiary: Color(0x8C1C1C1E),
    accent: _accent,
    danger: Color(0xFFE5484D),
    warning: Color(0xFFF2780C),
    success: Color(0xFF2EA44F),
    backdrop: Color(0x33000000),
  );

  static const dark = Tokens(
    background: Color(0xFF1A1A1C),
    sidebar: Color(0xFF141416),
    surface: Color(0xFF1F1F22),
    raised: Color(0xFF242427),
    border: Color(0xFF2E2E33),
    hover: Color(0x0FFFFFFF),
    selected: Color(0x1AFFFFFF),
    openHighlight: Color(0x263E7BFA),
    primary: Color(0xFFEDEDEF),
    secondary: Color(0x99EDEDEF),
    tertiary: Color(0x80EDEDEF),
    accent: _accent,
    danger: Color(0xFFFF6369),
    warning: Color(0xFFFF8B3E),
    success: Color(0xFF3FB950),
    backdrop: Color(0x66000000),
  );

  static Tokens of(BuildContext context) =>
      Theme.of(context).extension<Tokens>()!;

  /// The 16 named colors; neutral renders as plain secondary text color (SPEC §8.2). Each is at least 3:1 against
  /// every surface as a glyph (test/ui/design_system_test.dart), so some are darker in the light theme.
  Color named(TaskletColor color) {
    final dark = identical(this, Tokens.dark);
    return switch (color) {
      TaskletColor.blue => const Color(0xFF3E7BFA),
      TaskletColor.purple => const Color(0xFF8E5CF6),
      TaskletColor.green =>
        dark ? const Color(0xFF2EA44F) : const Color(0xFF22913F),
      TaskletColor.orange =>
        dark ? const Color(0xFFF2780C) : const Color(0xFFDD6A04),
      TaskletColor.red => const Color(0xFFE5484D),
      TaskletColor.yellow =>
        dark ? const Color(0xFFE2B203) : const Color(0xFFA67C00),
      TaskletColor.magenta => const Color(0xFFD946C6),
      TaskletColor.teal =>
        dark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
      TaskletColor.cyan =>
        dark ? const Color(0xFF22D3EE) : const Color(0xFF0891B2),
      TaskletColor.indigo =>
        dark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
      TaskletColor.pink =>
        dark ? const Color(0xFFF472B6) : const Color(0xFFDB2777),
      TaskletColor.lime =>
        dark ? const Color(0xFFA3E635) : const Color(0xFF4D7C0F),
      TaskletColor.amber =>
        dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      TaskletColor.brown =>
        dark ? const Color(0xFFC08A5B) : const Color(0xFF8B5E3C),
      TaskletColor.slate =>
        dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      TaskletColor.neutral => secondary,
    };
  }

  Color status(TaskStatus status) => switch (status) {
    TaskStatus.backlog || TaskStatus.todo => tertiary,
    TaskStatus.inProgress => const Color(0xFFE8A317),
    TaskStatus.done => accent,
  };

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(Tokens? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Type scale (SPEC §8.1): 12px body, 13px section titles, 14px page titles, 11px meta.
class TextStyles {
  static TextStyle body(BuildContext c) =>
      TextStyle(fontSize: 12, color: Tokens.of(c).primary, height: 1.35);
  static TextStyle bodySecondary(BuildContext c) =>
      body(c).copyWith(color: Tokens.of(c).secondary);
  static TextStyle meta(BuildContext c) =>
      TextStyle(fontSize: 11, color: Tokens.of(c).tertiary, height: 1.3);
  static TextStyle section(BuildContext c) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Tokens.of(c).primary,
  );
  static TextStyle sectionLabel(BuildContext c) => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Tokens.of(c).secondary,
  );
  static TextStyle pageTitle(BuildContext c) => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Tokens.of(c).primary,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final t = brightness == Brightness.light ? Tokens.light : Tokens.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: t.accent,
        brightness: brightness,
      ).copyWith(
        primary: t.accent,
        surface: t.background,
        onSurface: t.primary,
        outline: t.border,
        error: t.danger,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.background,
    canvasColor: t.background,
    dividerColor: t.border,
    extensions: [t],
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    hoverColor: t.hover,
    highlightColor: Colors.transparent,
    textTheme: Typography.material2021(platform: TargetPlatform.windows)
        .englishLike
        .apply(bodyColor: t.primary, displayColor: t.primary)
        .copyWith(bodyMedium: TextStyle(fontSize: 12, color: t.primary)),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: TextStyle(fontSize: 11, color: t.background),
      decoration: BoxDecoration(
        color: t.primary,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: t.border),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        // Disabled items (e.g. Move Up on the first project) must look disabled.
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? t.tertiary : t.primary,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? t.tertiary : t.secondary,
        ),
        iconSize: const WidgetStatePropertyAll(14),
        minimumSize: const WidgetStatePropertyAll(Size(180, 30)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        overlayColor: WidgetStatePropertyAll(t.hover),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      hintStyle: TextStyle(color: t.tertiary, fontSize: 12),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: t.border),
        borderRadius: BorderRadius.circular(6),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: t.border),
        borderRadius: BorderRadius.circular(6),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: t.accent),
        borderRadius: BorderRadius.circular(6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.primary,
        side: BorderSide(color: t.border),
        textStyle: const TextStyle(fontSize: 12),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.secondary,
        textStyle: const TextStyle(fontSize: 12),
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.border,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      thumbColor: WidgetStatePropertyAll(t.selected),
      radius: const Radius.circular(3),
    ),
  );
}
