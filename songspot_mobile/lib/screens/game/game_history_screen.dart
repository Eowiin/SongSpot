import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../models/history_day.dart';
import '../../services/api_service.dart';
import 'game_history_detail_screen.dart';

class GameHistoryScreen extends StatefulWidget {
  final String roomId;

  const GameHistoryScreen({super.key, required this.roomId});

  @override
  State<GameHistoryScreen> createState() => _GameHistoryScreenState();
}

class _GameHistoryScreenState extends State<GameHistoryScreen> {
  final ApiService _apiService = ApiService();
  final List<HistoryDay> _days = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _offset = 0;
  static const int _limit = 30;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _days.clear();
        _offset = 0;
        _hasMore = true;
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final data = await _apiService.getRoomHistory(
        widget.roomId,
        limit: _limit,
        offset: _offset,
      );
      final results = (data['results'] as List<dynamic>)
          .map((e) => HistoryDay.fromJson(e as Map<String, dynamic>))
          .toList();
      final total = data['total'] as int;

      if (mounted) {
        setState(() {
          _days.addAll(results);
          _offset += results.length;
          _hasMore = _offset < total;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _isLoading = false; _isLoadingMore = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; _isLoadingMore = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new),
                      onPressed: () => Navigator.of(context).pop(),
                      color: AppTheme.textPrimary,
                    ),
                    Text('History', style: Theme.of(context).textTheme.headlineMedium),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 48),
                                  const SizedBox(height: 16),
                                  Text(_error!, style: const TextStyle(color: AppTheme.errorColor), textAlign: TextAlign.center),
                                  const SizedBox(height: 16),
                                  TextButton(
                                    onPressed: () => _loadHistory(refresh: true),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _days.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.history, size: 64, color: AppTheme.textSecondary),
                                    const SizedBox(height: 16),
                                    Text('No history yet', style: Theme.of(context).textTheme.titleMedium),
                                    const SizedBox(height: 4),
                                    Text('Past days will appear here after noon UTC.', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                color: AppTheme.primaryColor,
                                onRefresh: () => _loadHistory(refresh: true),
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: (notification) {
                                    if (notification is ScrollEndNotification &&
                                        notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                                      _loadMore();
                                    }
                                    return false;
                                  },
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    itemCount: _days.length + (_isLoadingMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == _days.length) {
                                        return const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 16),
                                          child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor, strokeWidth: 2)),
                                        );
                                      }
                                      return _HistoryDayTile(
                                        day: _days[index],
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => GameHistoryDetailScreen(
                                              roomId: widget.roomId,
                                              date: _days[index].date,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
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

class _HistoryDayTile extends StatelessWidget {
  const _HistoryDayTile({required this.day, required this.onTap});

  final HistoryDay day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final session = day.mySession;
    final dateLabel = DateFormat('EEEE, MMM d yyyy').format(DateTime.parse(day.date));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.cardBorderRadius),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Cover thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: day.track.coverUrl != null
                      ? Image.network(
                          day.track.coverUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _coverPlaceholder(),
                        )
                      : _coverPlaceholder(),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        day.track.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        day.track.artist,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Result badge
                _ResultBadge(session: session),

                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: AppTheme.surfaceColor,
      child: const Icon(Icons.album, color: AppTheme.primaryColor),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.session});

  final HistorySession? session;

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('—', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary)),
      );
    }
    if (session!.correctGuess) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.successColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check, size: 14, color: AppTheme.successColor),
            const SizedBox(width: 4),
            Text(
              '+${session!.pointsEarned ?? 0}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.successColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.close, size: 14, color: AppTheme.errorColor),
    );
  }
}
