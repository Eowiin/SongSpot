import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/room_provider.dart';
import '../../widgets/gradient_button.dart';
import '../auth/login_screen.dart';
import '../game/game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _roomCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomProvider>().loadMyRooms();
    });
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateRoom() async {
    final roomProvider = context.read<RoomProvider>();
    final room = await roomProvider.createRoom();

    if (room != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GameScreen(roomId: room.id),
        ),
      );
    } else if (mounted && roomProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(roomProvider.errorMessage!),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _handleJoinRoom() async {
    final roomCode = _roomCodeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a room code'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final roomProvider = context.read<RoomProvider>();
    final room = await roomProvider.joinRoom(roomCode);

    if (room != null && mounted) {
      _roomCodeController.clear();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GameScreen(roomId: room.id),
        ),
      );
    } else if (mounted && roomProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(roomProvider.errorMessage!),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primaryColor,
                      child: Text(
                        user?.username[0].toUpperCase() ?? 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.username ?? 'User',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            user?.email ?? '',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: _handleLogout,
                      color: AppTheme.textPrimary,
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title
                      const Icon(
                        Icons.music_note,
                        size: 60,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'BlindTest Friends',
                        style: Theme.of(context).textTheme.displayMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      // Create Room Button
                      GradientButton(
                        text: 'Create New Room',
                        onPressed: _handleCreateRoom,
                        isLoading: context.watch<RoomProvider>().isLoading,
                      ),
                      const SizedBox(height: 24),

                      // Join Room Section
                      Text(
                        'Join a Room',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _roomCodeController,
                              decoration: InputDecoration(
                                hintText: 'Enter room code',
                                filled: true,
                                fillColor: AppTheme.surfaceColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [
                                UpperCaseTextFormatter(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            height: 56,
                            width: 56,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _handleJoinRoom,
                                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                                child: const Icon(Icons.arrow_forward, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),

                      // My Rooms Section
                      Text(
                        'My Rooms',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Consumer<RoomProvider>(
                        builder: (context, roomProvider, _) {
                          if (roomProvider.isLoading) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (roomProvider.myRooms.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                gradient: AppTheme.cardGradient,
                                borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.music_off,
                                    size: 48,
                                    color: AppTheme.textSecondary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No rooms yet',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Create or join a room to start playing!',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          }

                          return Column(
                            children: roomProvider.myRooms.map((room) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  gradient: AppTheme.cardGradient,
                                  borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => GameScreen(roomId: room.id),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.people,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Room ${room.roomCode}',
                                                  style: Theme.of(context).textTheme.titleLarge,
                                                ),
                                                Text(
                                                  '${room.userCount} member${room.userCount != 1 ? 's' : ''}',
                                                  style: Theme.of(context).textTheme.bodyMedium,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.arrow_forward_ios, size: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
