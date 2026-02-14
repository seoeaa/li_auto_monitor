import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/monitor_service.dart';
import '../widgets/host_card.dart';
import 'info.view.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MonitorService>(context, listen: false).startMonitoring();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Li Auto Monitor',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            Text(
              'Мониторинг сервисов',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InfoView()),
              );
            },
            icon: const Icon(Icons.info_outline, color: Colors.white70),
            tooltip: 'App Info',
          ),
          Consumer<MonitorService>(
            builder: (context, monitor, child) {
              return Container(
                margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: monitor.isMonitoring
                      ? const Color(0xFF00FFC2).withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: monitor.isMonitoring
                        ? const Color(0xFF00FFC2).withOpacity(0.3)
                        : Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    monitor.isMonitoring ? 'ЖИВОЙ' : 'ПАУЗА',
                    style: TextStyle(
                      color: monitor.isMonitoring
                          ? const Color(0xFF00FFC2)
                          : Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<MonitorService>(
        builder: (context, monitor, child) {
          if (monitor.hosts.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FFC2)),
            );
          }

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: monitor.hosts.length,
            padding: const EdgeInsets.only(top: 16, bottom: 32),
            itemBuilder: (context, index) {
              return HostCard(host: monitor.hosts[index]);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Provider.of<MonitorService>(context, listen: false).startMonitoring();
        },
        backgroundColor: const Color(0xFF00FFC2),
        child: const Icon(Icons.refresh, color: Colors.black),
      ),
    );
  }
}
