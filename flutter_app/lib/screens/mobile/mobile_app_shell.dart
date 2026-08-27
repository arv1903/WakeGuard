import 'package:flutter/material.dart';

import '../../services/connection_service.dart';
import '../../theme.dart';
import 'connection_setup_screen.dart';
import 'mobile_live_monitor_screen.dart';
import 'mobile_history_screen.dart';
import 'mobile_settings_screen.dart';
import 'mobile_post_trip_screen.dart';

/// Mobile shell with bottom navigation bar.
///
/// Shows [ConnectionSetupScreen] when no valid stored connection exists,
/// otherwise renders the 3-tab bottom nav (Monitor / History / Settings).
class MobileAppShell extends StatefulWidget {
  const MobileAppShell({super.key, required this.connectionService});

  final ConnectionService connectionService;

  @override
  State<MobileAppShell> createState() => _MobileAppShellState();
}

class _MobileAppShellState extends State<MobileAppShell> {
  int _selectedIndex = 0;
  bool _isSessionActive = false;

  @override
  void initState() {
    super.initState();
    widget.connectionService.client.addListener(_onClientUpdate);
    widget.connectionService.addListener(_onConnectionUpdate);
  }

  @override
  void dispose() {
    widget.connectionService.client.removeListener(_onClientUpdate);
    widget.connectionService.removeListener(_onConnectionUpdate);
    super.dispose();
  }

  void _onClientUpdate() {
    if (!mounted) return;
    final snap = widget.connectionService.client.snapshot;
    final active = snap.tripActive;
    if (active != _isSessionActive) {
      final sessionEnded = _isSessionActive && !active;
      setState(() {
        _isSessionActive = active;
        if (active) _selectedIndex = 0; // Switch to monitor on session start
      });
      if (sessionEnded) _showPostTripSummary();
    } else {
      setState(() {});
    }
  }

  void _showPostTripSummary() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MobilePostTripScreen(
          client: widget.connectionService.client,
        ),
      ),
    );
  }

  void _onConnectionUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.connectionService;

    // Show setup screen if not connected / no stored credentials
    if (!cs.isInitialised) {
      return const Scaffold(
        backgroundColor: Stitch.background,
        body: Center(
          child: CircularProgressIndicator(color: Stitch.primary),
        ),
      );
    }

    if (!cs.isPaired || cs.isExpired) {
      return ConnectionSetupScreen(connectionService: cs);
    }

    return _buildShell();
  }

  Widget _buildShell() {
    return Scaffold(
      backgroundColor: Stitch.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top header
            _buildHeader(),
            // Page content
            Expanded(child: _buildPage()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    final titles = ['Monitor', 'History', 'Settings'];
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Stitch.surface.withValues(alpha: 0.8),
        border: const Border(
          bottom: BorderSide(
            color: Stitch.containerHighest,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            titles[_selectedIndex],
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Stitch.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          // Connection status avatar
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Stitch.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              size: 18,
              color: Stitch.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    final client = widget.connectionService.client;
    switch (_selectedIndex) {
      case 0:
        return MobileLiveMonitorScreen(
          client: client,
          sessionStartTime: null,
        );
      case 1:
        return MobileHistoryScreen(client: client);
      case 2:
        return MobileSettingsScreen(
          connectionService: widget.connectionService,
          onForgetDevice: () {
            setState(() {}); // Rebuild to show setup screen
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBottomNav() {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
      decoration: const BoxDecoration(
        color: Stitch.container,
        border: Border(
          top: BorderSide(color: Stitch.containerHighest, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.visibility,
              label: 'Monitor',
              selected: _selectedIndex == 0,
              onTap: () => setState(() => _selectedIndex = 0),
            ),
            _NavItem(
              icon: Icons.history,
              label: 'History',
              selected: _selectedIndex == 1,
              onTap: () => setState(() => _selectedIndex = 1),
            ),
            _NavItem(
              icon: Icons.settings,
              label: 'Settings',
              selected: _selectedIndex == 2,
              onTap: () => setState(() => _selectedIndex = 2),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Nav Item ────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Stitch.primary : Stitch.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: color,
              // Fill the icon when selected (Material Symbols weight variation)
              opticalSize: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
