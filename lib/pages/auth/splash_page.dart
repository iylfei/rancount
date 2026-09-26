import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../styles/liquid_theme.dart';
import '../../styles/tokens.dart';
import '../../widgets/ui/liquid_glass.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    if (LiquidTheme.isActive(context)) {
      return _buildLiquidSplash(context);
    }

    return Scaffold(
      backgroundColor: primaryColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo区域
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Image.asset('assets/logo2.png', fit: BoxFit.contain),
                ),
              ),

              const SizedBox(height: 32),

              // 应用名称
              Text(
                AppLocalizations.of(context).splashAppName,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 16),

              // Slogan
              Text(
                AppLocalizations.of(context).splashSlogan,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(flex: 3),

              // 数据安全说明
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.security_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context).splashSecurityTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${AppLocalizations.of(context).splashSecurityFeature1}\n'
                      '${AppLocalizations.of(context).splashSecurityFeature2}\n'
                      '${AppLocalizations.of(context).splashSecurityFeature3}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 加载指示器
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                AppLocalizations.of(context).splashInitializing,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.8),
                ),
              ),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiquidSplash(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return LiquidBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 48,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassSurface(
                      borderRadius: 34,
                      padding: const EdgeInsets.all(24),
                      child: Image.asset(
                        'assets/logo2.png',
                        width: 72,
                        height: 72,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      l10n.splashAppName,
                      textAlign: TextAlign.center,
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.splashSlogan,
                      textAlign: TextAlign.center,
                      style: text.titleMedium?.copyWith(
                        color: BeeTokens.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 48),
                    GlassSurface(
                      prominent: false,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                color: BeeTokens.primary(context),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  l10n.splashSecurityTitle,
                                  style: text.titleSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '${l10n.splashSecurityFeature1}\n'
                            '${l10n.splashSecurityFeature2}\n'
                            '${l10n.splashSecurityFeature3}',
                            style: text.bodyMedium?.copyWith(
                              color: BeeTokens.textSecondary(context),
                              height: 1.65,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.splashInitializing,
                      style: text.bodySmall?.copyWith(
                        color: BeeTokens.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
