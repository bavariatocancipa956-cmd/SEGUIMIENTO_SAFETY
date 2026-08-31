import 'package:flutter/material.dart';
import 'dashboard_roturas_screen.dart';
import 'reporte_hora_hora_screen.dart';
import 'dashboard_estibas_screen.dart';
import 'estibas_entregadas_screen.dart';
import 'inventario_estibas_screen.dart';
import 'dashboard_sorting_screen.dart';
import 'dashboard_ai_screen.dart';
import 'dashboard_fms_screen.dart';
import 'dashboard_fms_maquinas_screen.dart';
import 'fms_areas_screen.dart';
import 'fms_metas_screen.dart';
import 'fms_tendencias_screen.dart';
import 'fms_tendencias_operadores_screen.dart';
import 'fms_abordajes_screen.dart';

class PantallaPrincipal extends StatefulWidget {
  final Map<String, dynamic>? datosUsuario;

  const PantallaPrincipal({super.key, this.datosUsuario});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> with SingleTickerProviderStateMixin {
  bool _menuSeguridadExpandido = true;
  bool _menuFmsExpandido = true;
  bool _menuRoturaExpandido = false;

  bool _menuReprocesosExpandido = true;
  bool _menuEstibasExpandido = true;

  bool _menuControlesExpandido = true;

  bool _mostrarSidebar = true;

  String _vistaActual = 'DASHBOARD_AI';

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
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _mostrarSidebar ? _buildSidebar() : const SizedBox.shrink(),
          ),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ClipRect(
                    child: _obtenerVistaActual(),
                  ),
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
      case 'SORTING':
        return DashboardSortingScreen(onToggleSidebar: _toggleSidebar);
      case 'ROTURA_DASHBOARD':
        return DashboardRoturasScreen(onToggleSidebar: _toggleSidebar);
      case 'ROTURA_HORA_HORA':
        return ReporteHoraHoraScreen(onToggleSidebar: _toggleSidebar);
      case 'REPROCESOS_ESTIBAS':
        return DashboardEstibasScreen(onToggleSidebar: _toggleSidebar);
      case 'ENTREGA_ESTIBAS':
        return const EstibasEntregadasScreen();
      case 'INVENTARIO_ESTIBAS':
        return const InventarioEstibasScreen();

      case 'DASHBOARD_AI':
        return DashboardAiScreen(
          datosEmpleado: widget.datosUsuario,
          onToggleSidebar: _toggleSidebar,
        );

      case 'DASHBOARD_FMS':
        return DashboardFmsScreen(onToggleSidebar: _toggleSidebar);

      case 'DASHBOARD_FMS_MAQUINAS':
        return DashboardFmsMaquinasScreen(onToggleSidebar: _toggleSidebar);

      case 'FMS_AREAS':
        return DashboardFmsAreasScreen(onToggleSidebar: _toggleSidebar);

      case 'METAS_FMS':
        return FmsMetasScreen(onToggleSidebar: _toggleSidebar);

      case 'TENDENCIAS_FMS':
        return FmsTendenciasScreen(onToggleSidebar: _toggleSidebar);

      case 'TENDENCIAS_OPERADORES':
        return FmsTendenciasOperadoresScreen(onToggleSidebar: _toggleSidebar);

      case 'FMS_ABORDAJES':
        return FmsAbordajesScreen(onToggleSidebar: _toggleSidebar);

      default:
        return const Center(child: Text('Seleccione una opción del menú'));
    }
  }

  String _obtenerTituloHeader() {
    switch (_vistaActual) {
      case 'SORTING': return 'PLANTA TOCANCIPÁ - DASHBOARD SORTING';
      case 'ROTURA_DASHBOARD': return 'PLANTA TOCANCIPÁ - DASHBOARD ROTURAS';
      case 'ROTURA_HORA_HORA': return 'PLANTA TOCANCIPÁ - REPORTE HORA A HORA';
      case 'REPROCESOS_ESTIBAS': return 'PLANTA TOCANCIPÁ - REPARACIÓN DE ESTIBAS';
      case 'ENTREGA_ESTIBAS': return 'PLANTA TOCANCIPÁ - ENTREGA DE ESTIBAS';
      case 'INVENTARIO_ESTIBAS': return 'PLANTA TOCANCIPÁ - INVENTARIO DE ESTIBAS';
      case 'DASHBOARD_FMS': return 'PLANTA TOCANCIPÁ - DASHBOARD FMS';
      case 'DASHBOARD_FMS_MAQUINAS': return 'PLANTA TOCANCIPÁ - DASHBOARD MÁQUINAS';
      case 'FMS_AREAS': return 'PLANTA TOCANCIPÁ - FMS ÁREAS';
      case 'METAS_FMS': return 'PLANTA TOCANCIPÁ - CUMPLIMIENTO METAS FMS';
      case 'TENDENCIAS_FMS': return 'PLANTA TOCANCIPÁ - TENDENCIAS SUPERVISORES';
      case 'TENDENCIAS_OPERADORES': return 'PLANTA TOCANCIPÁ - TENDENCIAS OPERADORES';
      case 'FMS_ABORDAJES': return 'PLANTA TOCANCIPÁ - ABORDAJES FMS';
      case 'DASHBOARD_AI': return 'PLANTA TOCANCIPÁ - DASHBOARD REVISIÓN AI';

      default: return 'OPERACIÓN TOCANCIPÁ';
    }
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: const Color(0xFF0F1522),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 25, top: 10),
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

          _buildGrupoExpandible(
            titulo: 'SEGURIDAD',
            expandido: _menuSeguridadExpandido,
            onTap: () => setState(() => _menuSeguridadExpandido = !_menuSeguridadExpandido),
            submenus: [
              _buildSubGrupoExpandible(
                titulo: 'FMS',
                expandido: _menuFmsExpandido,
                onTap: () => setState(() => _menuFmsExpandido = !_menuFmsExpandido),
                submenus: [
                  _buildOpcionSubmenu(
                    titulo: 'SEGUIMIENTO FMS',
                    idVista: 'DASHBOARD_FMS',
                    icono: Icons.local_shipping_rounded,
                    nivel: 3,
                  ),
                  _buildOpcionSubmenu(
                    titulo: 'SEGUIMIENTO MAQUINAS',
                    idVista: 'DASHBOARD_FMS_MAQUINAS',
                    icono: Icons.local_shipping_rounded,
                    nivel: 3,
                  ),
                  _buildOpcionSubmenu(
                    titulo: 'FMS ÁREAS',
                    idVista: 'FMS_AREAS',
                    icono: Icons.local_shipping_rounded,
                    nivel: 3,
                  ),
                  _buildOpcionSubmenu(
                    titulo: 'METAS FMS',
                    idVista: 'METAS_FMS',
                    icono: Icons.local_shipping_rounded,
                    nivel: 3,
                  ),
                  _buildOpcionSubmenu(
                    titulo: 'TEND.SUPER.',
                    idVista: 'TENDENCIAS_FMS',
                    icono: Icons.local_shipping_rounded,
                    nivel: 3,
                  ),
                  _buildOpcionSubmenu(
                    titulo: 'TEND. OPERA.',
                    idVista: 'TENDENCIAS_OPERADORES',
                    icono: Icons.local_shipping_rounded,
                    nivel: 3,
                  ),
                  _buildOpcionSubmenu(
                    titulo: 'CUMP. ABORDAJES',
                    idVista: 'FMS_ABORDAJES',
                    icono: Icons.local_shipping_rounded,
                    nivel: 3,
                  ),
                ],
              ),
              _buildSubGrupoExpandible(
                titulo: 'ROTURA',
                expandido: _menuRoturaExpandido,
                onTap: () => setState(() => _menuRoturaExpandido = !_menuRoturaExpandido),
                submenus: [
                  _buildOpcionSubmenu(titulo: 'Dashboard Roturas', idVista: 'ROTURA_DASHBOARD', icono: Icons.analytics_outlined, nivel: 3),
                  _buildOpcionSubmenu(titulo: 'Reporte Hora a Hora', idVista: 'ROTURA_HORA_HORA', icono: Icons.access_time_rounded, nivel: 3),
                ],
              ),
            ],
          ),

          _buildGrupoExpandible(
            titulo: 'REPROCESOS',
            expandido: _menuReprocesosExpandido,
            onTap: () => setState(() => _menuReprocesosExpandido = !_menuReprocesosExpandido),
            submenus: [
              _buildSubGrupoExpandible(
                titulo: 'ESTIBAS',
                expandido: _menuEstibasExpandido,
                onTap: () => setState(() => _menuEstibasExpandido = !_menuEstibasExpandido),
                submenus: [
                  _buildOpcionSubmenu(titulo: 'Reparación de Estibas', idVista: 'REPROCESOS_ESTIBAS', icono: Icons.bar_chart_rounded, nivel: 3),
                  _buildOpcionSubmenu(titulo: 'Entrega de Estibas', idVista: 'ENTREGA_ESTIBAS', icono: Icons.local_shipping_outlined, nivel: 3),
                  _buildOpcionSubmenu(titulo: 'Inventario Estibas', idVista: 'INVENTARIO_ESTIBAS', icono: Icons.inventory_rounded, nivel: 3),
                ],
              ),
            ],
          ),

          _buildGrupoExpandible(
            titulo: 'CONTROLES',
            expandido: _menuControlesExpandido,
            onTap: () => setState(() => _menuControlesExpandido = !_menuControlesExpandido),
            submenus: [
              _buildOpcionSubmenu(titulo: 'Sorting', idVista: 'SORTING', icono: Icons.sort_rounded, nivel: 2),
              _buildOpcionSubmenu(titulo: 'Dashboard Revisión AI', idVista: 'DASHBOARD_AI', icono: Icons.analytics_outlined, nivel: 2),
            ],
          ),
        ],
      ),
    );
  }

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
          splashColor: Colors.white10,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                AnimatedRotation(
                  turns: expandido ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expandido
              ? Column(children: submenus)
              : const SizedBox(width: double.infinity, height: 0),
        ),
        Divider(color: Colors.white.withOpacity(0.05), height: 1, thickness: 1),
      ],
    );
  }

  Widget _buildSubGrupoExpandible({
    required String titulo,
    required bool expandido,
    required VoidCallback onTap,
    required List<Widget> submenus,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          splashColor: Colors.white10,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.only(left: 28, right: 20, top: 10, bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Color(0xFF8E95A5),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                AnimatedRotation(
                  turns: expandido ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF8E95A5),
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expandido
              ? Column(children: submenus)
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Widget _buildOpcionSubmenu({
    required String titulo,
    required String idVista,
    required IconData icono,
    int nivel = 2,
  }) {
    bool activo = _vistaActual == idVista;
    double margenIzquierdo = nivel == 3 ? 24.0 : 10.0;

    return Padding(
      padding: EdgeInsets.only(left: margenIzquierdo, right: 10, bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _vistaActual = idVista),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          decoration: BoxDecoration(
            color: activo ? const Color(0xFF241C25) : Colors.transparent,
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
                      width: 4,
                      color: const Color(0xFFE11D48),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: Row(
                      children: [
                        Icon(
                          icono,
                          color: activo ? Colors.white : const Color(0xFF748297),
                          size: nivel == 3 ? 18 : 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            titulo,
                            style: TextStyle(
                              color: activo ? Colors.white : const Color(0xFF748297),
                              fontSize: nivel == 3 ? 13 : 14,
                              fontWeight: activo ? FontWeight.w600 : FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
              color: Colors.red[900],
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}