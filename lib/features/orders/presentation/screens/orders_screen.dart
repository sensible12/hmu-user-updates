import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/demo_data_service.dart';
import '../../../../core/services/mpesa_service.dart';
import '../../../../core/services/network_error_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/models/order_summary.dart';
import '../../data/repositories/order_repository.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  final OrderRepository _orderRepository = OrderRepository();
  final DemoDataService _demoDataService = DemoDataService();
  late final AnimationController _payNowPulseController;

  List<OrderSummary> orders = <OrderSummary>[];
  bool loading = true;
  bool seeding = false;
  String orderView = 'current';
  String filter = 'all';
  String? expandedOrder;
  String? orderError;
  RealtimeChannel? _ordersChannel;
  Timer? _realtimeRefreshDebounce;
  final Set<String> _processingPaymentOrderIds = <String>{};

  final List<String> currentStatusOrder = <String>[
    'all',
    'pending',
    'accepted',
    'preparing',
    'on_the_way',
  ];

  final List<String> historyStatusOrder = <String>[
    'all',
    'completed',
    'delivered',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _payNowPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _restoreCachedOrders();
    fetchOrders(showLoadingIndicator: orders.isEmpty);
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _payNowPulseController.dispose();
    _realtimeRefreshDebounce?.cancel();
    final ordersChannel = _ordersChannel;
    if (ordersChannel != null) {
      SupabaseService.client.removeChannel(ordersChannel);
    }
    super.dispose();
  }

  void _restoreCachedOrders() {
    final user = SupabaseService.currentUser;
    if (user == null) {
      return;
    }

    final cached = _orderRepository.getCachedOrdersForUser(user.id);
    if (cached == null || cached.isEmpty) {
      return;
    }

    orders = cached;
    loading = false;
  }

  void _subscribeToRealtime() {
    final user = SupabaseService.currentUser;
    if (user == null) {
      return;
    }

    _ordersChannel = SupabaseService.client
        .channel('orders-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: user.id,
          ),
          callback: (_) => _scheduleOrdersRefresh(),
        )
        .subscribe();
  }

  void _scheduleOrdersRefresh() {
    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      fetchOrders(forceRefresh: true, showLoadingIndicator: false);
    });
  }

  Future<void> fetchOrders({
    bool forceRefresh = false,
    bool showLoadingIndicator = true,
  }) async {
    if (showLoadingIndicator && orders.isEmpty) {
      setState(() {
        loading = true;
        orderError = null;
      });
    } else if (orderError != null) {
      setState(() => orderError = null);
    }

    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            orders = <OrderSummary>[];
            loading = false;
          });
        }
        return;
      }

      final results = await _orderRepository.fetchOrdersForUser(
        user.id,
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        orders = results;
        loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          orderError = NetworkErrorService.toUserMessage(error);
          loading = false;
        });
      }
    }
  }

  Future<void> seedDemoData() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in first to generate demo orders.')),
      );
      return;
    }

    setState(() => seeding = true);

    try {
      await _demoDataService.seedDemoCatalogAndOrders();
      OrderRepository.clearCache(user.id);
      await fetchOrders(forceRefresh: true, showLoadingIndicator: false);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo orders generated.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate demo orders: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => seeding = false);
      }
    }
  }

  Future<void> onRefresh() =>
      fetchOrders(forceRefresh: true, showLoadingIndicator: false);

  List<OrderSummary> get filteredOrders {
    final source = orderView == 'history' ? historyOrders : currentOrders;

    if (filter == 'all') {
      return source;
    }

    return source.where((order) => order.status == filter).toList();
  }

  List<OrderSummary> get currentOrders => orders
      .where((order) => !_isHistoryStatus(order.status))
      .toList();

  List<OrderSummary> get historyOrders => orders
      .where((order) => _isHistoryStatus(order.status))
      .toList();

  bool _isHistoryStatus(String status) {
    return status == 'completed' || status == 'cancelled' || status == 'delivered';
  }

  String formatCurrency(int cents) => 'M ${(cents / 100).toStringAsFixed(2)}';
  String formatWholeAmount(int amount) => 'M ${amount.toStringAsFixed(2)}';

  void toggleExpand(String id) {
    setState(() {
      expandedOrder = expandedOrder == id ? null : id;
    });
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.green;
      case 'preparing':
        return Colors.blue;
      case 'on_the_way':
        return Colors.teal;
      case 'completed':
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool _canPayForOrder(OrderSummary order) {
    final mpesaTransactionId = order.mpesaTransactionId?.trim() ?? '';
    return order.status == 'accepted' && mpesaTransactionId.isEmpty;
  }

  Future<String?> _promptForMpesaNumber() async {
    final defaultPhone = SupabaseService.currentUser?.userMetadata?['phone']
            ?.toString()
            .trim() ??
        '';
    final controller = TextEditingController(
      text: defaultPhone.isNotEmpty ? defaultPhone : '266',
    );

    final number = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Pay with M-Pesa'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'M-Pesa number',
              hintText: '26650123456',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Pay now'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return number;
  }

  Future<void> _payForOrder(OrderSummary order) async {
    if (_processingPaymentOrderIds.contains(order.id)) {
      return;
    }

    final customerMsisdn = await _promptForMpesaNumber();
    if (customerMsisdn == null || customerMsisdn.isEmpty) {
      return;
    }

    setState(() {
      _processingPaymentOrderIds.add(order.id);
    });

    try {
      final result = await MpesaService.processOrderPayment(
        orderId: order.id,
        customerMSISDN: customerMsisdn,
      );

      OrderRepository.clearCache(SupabaseService.currentUser?.id);
      await fetchOrders(forceRefresh: true, showLoadingIndicator: false);

      if (!mounted) {
        return;
      }

      final message = result.payoutPending
          ? 'Payment successful. Restaurant payout is pending.'
          : 'Payment successful. Restaurant payout sent.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      final paymentMessage = NetworkErrorService.isConnectivityIssue(error)
          ? NetworkErrorService.defaultNoInternetMessage
          : 'Payment failed: ${NetworkErrorService.toUserMessage(error)}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(paymentMessage)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingPaymentOrderIds.remove(order.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: loading && orders.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : orderError != null && orders.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            orderError == NetworkErrorService.defaultNoInternetMessage
                                ? Icons.wifi_off_rounded
                                : Icons.receipt_long_outlined,
                            size: 48,
                            color: orderError == NetworkErrorService.defaultNoInternetMessage
                                ? const Color(0xFFE53935)
                                : null,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            orderError == NetworkErrorService.defaultNoInternetMessage
                                ? 'No Internet Connection'
                                : 'Unable to load orders',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            orderError!,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: fetchOrders,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
            : RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'My Orders',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                        ),
                        Text('${filteredOrders.length} ${orderView == 'history' ? 'in history' : 'active'}'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Current'),
                            selected: orderView == 'current',
                            onSelected: (_) {
                              setState(() {
                                orderView = 'current';
                                filter = 'all';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('History'),
                            selected: orderView == 'history',
                            onSelected: (_) {
                              setState(() {
                                orderView = 'history';
                                filter = 'all';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: (orderView == 'history'
                                ? historyStatusOrder
                                : currentStatusOrder)
                            .map((status) {
                          final active = filter == status;
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: ChoiceChip(
                              label: Text(
                                status == 'all' ? 'All' : status.replaceAll('_', ' '),
                              ),
                              selected: active,
                              onSelected: (_) => setState(() => filter = status),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (filteredOrders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          children: [
                            Text(
                              orderView == 'history'
                                  ? 'No order history found'
                                  : 'No active orders found',
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: seeding ? null : seedDemoData,
                              icon: const Icon(Icons.auto_awesome),
                              label: Text(
                                seeding ? 'Generating demo orders...' : 'Generate demo orders',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ...filteredOrders.map(buildOrderCard),
                  ],
                ),
              ),
      ),
    );
  }

  Widget buildOrderCard(OrderSummary item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shadowColor = Colors.black.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.08,
    );
    final firstImage = item.items.isNotEmpty ? item.items.first.imageUrl : null;
    final createdText = item.createdAt?.toLocal().toString() ?? 'Unknown date';
    final id = item.id;
    final shortId = id.length <= 6 ? id.toUpperCase() : id.substring(0, 6).toUpperCase();
    final displayOrderNumber =
        item.orderNumber == null || item.orderNumber!.trim().isEmpty
            ? shortId
            : item.orderNumber!;
    final canPayNow = _canPayForOrder(item);
    final isProcessingPayment = _processingPaymentOrderIds.contains(item.id);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: shadowColor, blurRadius: 6),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (firstImage != null)
                Image.network(
                  firstImage,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 72,
                      height: 72,
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.fastfood),
                    );
                  },
                )
              else
                Container(
                  width: 72,
                  height: 72,
                  color: scheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Icon(Icons.fastfood),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #$displayOrderNumber',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(createdText),
                    Text('${item.items.length} items'),
                    Text(
                      item.serviceType == 'delivery' ? 'Delivery order' : 'Pick-up order',
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: getStatusColor(item.status),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.status.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatCurrency(item.totalCents),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (canPayNow) ...[
                    const SizedBox(height: 8),
                    _PayNowAttentionRing(
                      animation: _payNowPulseController,
                      active: !isProcessingPayment,
                      color: scheme.primary,
                      child: SizedBox(
                        height: 32,
                        child: FilledButton.tonal(
                          onPressed: isProcessingPayment
                              ? null
                              : () => _payForOrder(item),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: isProcessingPayment
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Pay now'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (canPayNow)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Restaurant accepted this order. Complete payment to confirm it.',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => toggleExpand(id),
              child: Text(expandedOrder == id ? 'Hide details' : 'View details'),
            ),
          ),
          if (expandedOrder == id)
            Column(
              children: [
                ...item.items.map((entry) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.name),
                    subtitle: Text(formatCurrency(entry.priceCents * entry.quantity)),
                    trailing: entry.imageUrl != null
                        ? Image.network(
                            entry.imageUrl!,
                            width: 48,
                            height: 48,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 48,
                                height: 48,
                                color: scheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: const Icon(Icons.fastfood, size: 20),
                              );
                            },
                          )
                        : null,
                  );
                }),
                if (item.serviceType == 'delivery' && item.deliveryFee > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Delivery fee',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          formatWholeAmount(item.deliveryFee),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PayNowAttentionRing extends StatelessWidget {
  const _PayNowAttentionRing({
    required this.animation,
    required this.active,
    required this.color,
    required this.child,
  });

  final Animation<double> animation;
  final bool active;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return child;
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final pulse = Curves.easeOut.transform(animation.value);
        final ringOpacity = (1 - pulse) * 0.72;
        final ringSpread = 3 + (pulse * 7);

        return Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: ringOpacity),
                blurRadius: ringSpread,
                spreadRadius: pulse * 2,
              ),
            ],
            border: Border.all(
              color: color.withValues(alpha: 0.55 + (0.25 * (1 - pulse))),
              width: 1.4,
            ),
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}
