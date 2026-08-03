import 'package:flutter/material.dart';
import 'dashboard_roturas_screen.dart';
import 'reporte_hora_hora_screen.dart'; // 👈 IMPORTADO

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  // Estados para controlar desplegables
  bool _menuSafetyExpandido = true;
  bool _menuRoturaExpandido = true;

  bool _mostrarSidebar = true;

  // Vista inicial predeterminada
  String _vistaActual = 'ROTURA_DASHBOARD';

  void _toggleSidebar() {
    setState(() {
      _mostrarSidebar = !_mostrarSidebar;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F9),
      body: Row(
        children: [
          if (_mostrarSidebar) _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _obtenerVistaActual(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _obtenerVistaActual() {
    switch (_vistaActual) {
      case 'ROTURA_DASHBOARD':
        return DashboardRoturasScreen(onToggleSidebar: _toggleSidebar);
      case 'ROTURA_HORA_HORA':
        return ReporteHoraHoraScreen(onToggleSidebar: _toggleSidebar); // 👈 CONECTADO
      case 'DTO':
        return const Center(child: Text('Módulo DTO (En construcción)', style: TextStyle(color: Colors.grey, fontSize: 16)));
      case 'RUTINA_SAFETY':
        return const Center(child: Text('Módulo Rutina Safety (En construcción)', style: TextStyle(color: Colors.grey, fontSize: 16)));
      case 'RAYONES':
        return const Center(child: Text('Módulo Rayones (En construcción)', style: TextStyle(color: Colors.grey, fontSize: 16)));
      case 'VAS':
        return const Center(child: Text('Módulo VAS (En construcción)', style: TextStyle(color: Colors.grey, fontSize: 16)));
      case 'FMS':
        return const Center(child: Text('Módulo FMS (En construcción)', style: TextStyle(color: Colors.grey, fontSize: 16)));
      default:
        return const Center(child: Text('Seleccione una opción del menú'));
    }
  }

  String _obtenerTituloHeader() {
    switch (_vistaActual) {
      case 'ROTURA_DASHBOARD': return 'PLANTA TOCANCIPÁ - DASHBOARD ROTURAS';
      case 'ROTURA_HORA_HORA': return 'PLANTA TOCANCIPÁ - REPORTE HORA A HORA';
      case 'DTO': return 'PLANTA TOCANCIPÁ - CONTROL DTO';
      case 'RUTINA_SAFETY': return 'PLANTA TOCANCIPÁ - RUTINA SAFETY';
      case 'RAYONES': return 'PLANTA TOCANCIPÁ - CONTROL RAYONES';
      case 'VAS': return 'PLANTA TOCANCIPÁ - CONTROL VAS';
      case 'FMS': return 'PLANTA TOCANCIPÁ - MÓDULO FMS';
      default: return 'OPERACIÓN TOCANCIPÁ';
    }
  }

  Widget _buildSidebar() {
    return Container(
      width: 230,
      color: const Color(0xFF0B0E17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 25),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Colors.redAccent, size: 24),
                const SizedBox(width: 8),
                Text(
                  'OPERACIÓN TOCANCIPÁ',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // NIVEL 1: GRUPO SAFETY
          _buildGrupoExpandible(
            titulo: 'SAFETY',
            expandido: _menuSafetyExpandido,
            onTap: () => setState(() => _menuSafetyExpandido = !_menuSafetyExpandido),
            submenus: [
              // NIVEL 2: SUBGRUPO ROTURA (EXPANDIBLE)
              _buildSubGrupoExpandible(
                titulo: 'ROTURA',
                expandido: _menuRoturaExpandido,
                onTap: () => setState(() => _menuRoturaExpandido = !_menuRoturaExpandido),
                submenus: [
                  // NIVEL 3: OPCIONES INTERNAS DE ROTURA
                  _buildOpcionNivel3('DASHBOARD', 'ROTURA_DASHBOARD'),
                  _buildOpcionNivel3('REPORTE HORA A HORA', 'ROTURA_HORA_HORA'),
                ],
              ),

              // OTRAS OPCIONES DE NIVEL 2
              _buildOpcionSubmenu('DTO', 'DTO'),
              _buildOpcionSubmenu('RUTINA SAFETY', 'RUTINA_SAFETY'),
              _buildOpcionSubmenu('RAYONES', 'RAYONES'),
              _buildOpcionSubmenu('VAS', 'VAS'),
              _buildOpcionSubmenu('FMS', 'FMS'),
            ],
          ),
        ],
      ),
    );
  }

  // Contenedor principal desplegable (SAFETY)
  Widget _buildGrupoExpandible({
    required String titulo,
    required bool expandido,
    required VoidCallback onTap,
    required List<Widget> submenus,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                Icon(
                  expandido ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (expandido) ...submenus,
      ],
    );
  }

  // Subgrupo desplegable secundario (ROTURA)
  Widget _buildSubGrupoExpandible({
    required String titulo,
    required bool expandido,
    required VoidCallback onTap,
    required List<Widget> submenus,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Icon(
                    expandido ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey.shade500,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expandido) ...submenus,
      ],
    );
  }

  // Opciones de nivel 2 directas (DTO, RAYONES, etc.)
  Widget _buildOpcionSubmenu(String titulo, String idVista) {
    bool activo = _vistaActual == idVista;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _vistaActual = idVista),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: activo ? const Color(0xFF1B1E2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                if (activo)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 3.5,
                      color: Colors.redAccent,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      titulo,
                      style: TextStyle(
                        color: activo ? Colors.white : const Color(0xFF8E95A5),
                        fontSize: 12,
                        fontWeight: activo ? FontWeight.bold : FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Opciones de nivel 3 (Anidadas con mayor sangría interna)
  Widget _buildOpcionNivel3(String titulo, String idVista) {
    bool activo = _vistaActual == idVista;

    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 10, top: 2, bottom: 2),
      child: InkWell(
        onTap: () => setState(() => _vistaActual = idVista),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: activo ? const Color(0xFF1B1E2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                if (activo)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 3.5,
                      color: Colors.redAccent,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(
                      titulo,
                      style: TextStyle(
                        color: activo ? Colors.white : const Color(0xFF8E95A5),
                        fontSize: 11,
                        fontWeight: activo ? FontWeight.bold : FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Colors.white,
      child: Row(
        children: [
          InkWell(
            onTap: _toggleSidebar,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(Icons.menu_rounded, color: Colors.black87, size: 26),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _obtenerTituloHeader(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.red.shade900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}