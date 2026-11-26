#!/usr/bin/env python3
"""
tools/generate_manifest.py
===========================
Generador determinista de manifiestos package.xml para Salesforce DX.
Inspecciona los cambios reales en Git asociados a una solución o commit delta,
evitando omitir metadatos dependientes (LWC, Tab, FlexiPage, App, CustomField, PermSet).

Uso:
    # Generar manifiesto a partir de los commits locales de la solución o branch actual
    python3 tools/generate_manifest.py --solution SOL-0369
    
    # Generar filtrando por archivos o commits específicos
    python3 tools/generate_manifest.py --solution SOL-0369 --commits 5
    python3 tools/generate_manifest.py --solution SOL-0369 --base origin/main
"""

import os
import sys
import argparse
import subprocess
import xml.etree.ElementTree as ET
from xml.dom import minidom
from collections import defaultdict

FOLDER_TO_METADATA = {
    'classes': 'ApexClass',
    'triggers': 'ApexTrigger',
    'lwc': 'LightningComponentBundle',
    'aura': 'AuraDefinitionBundle',
    'flexipages': 'FlexiPage',
    'tabs': 'CustomTab',
    'permissionsets': 'PermissionSet',
    'profiles': 'Profile',
    'applications': 'CustomApplication',
    'flows': 'Flow',
    'flowDefinitions': 'FlowDefinition',
    'quickActions': 'QuickAction',
    'approvalProcesses': 'ApprovalProcess',
    'customMetadata': 'CustomMetadata',
    'objects': 'CustomObject',
    'layouts': 'Layout',
    'reports': 'Report',
    'dashboards': 'Dashboard',
    'notificationtypes': 'CustomNotificationType',
    'contentassets': 'ContentAsset',
    'staticresources': 'StaticResource'
}

def run_git_command(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]

def get_changed_files(sol_id, commits_count=None, base_branch=None):
    files = set()
    
    # 1. Buscar commits que mencionen la solución (ej. SOL-0369)
    if sol_id:
        matching_commits = run_git_command(f'git log --all --grep="{sol_id}" --format="%H"')
        for c in matching_commits:
            commit_files = run_git_command(f'git show --name-only --format="" {c}')
            files.update(commit_files)
            
    # 2. Si se especificó base_branch (ej: origin/develop o origin/main)
    if base_branch:
        diff_files = run_git_command(f'git diff --name-only {base_branch}...HEAD')
        files.update(diff_files)
        
    # 3. Si se especificó número de commits recientes
    if commits_count:
        recent_files = run_git_command(f'git log -n {commits_count} --name-only --format=""')
        files.update(recent_files)
        
    # 4. Incluir cambios locales en stage o sin comitear
    uncommitted = run_git_command('git status --porcelain')
    for line in uncommitted:
        parts = line.split()
        if len(parts) >= 2:
            files.add(parts[-1])
            
    return sorted(list(files))

def extract_metadata_members(changed_files):
    metadata_map = defaultdict(set)
    
    for f in changed_files:
        if not f.startswith('force-app/main/default/'):
            continue
            
        rel = f.replace('force-app/main/default/', '')
        parts = rel.split('/')
        if len(parts) < 2:
            continue
            
        folder = parts[0]
        filename = parts[1]
        
        if folder == 'classes':
            if filename.endswith('.cls') or filename.endswith('.cls-meta.xml'):
                member = filename.split('.')[0]
                metadata_map['ApexClass'].add(member)
        elif folder == 'triggers':
            if filename.endswith('.trigger') or filename.endswith('.trigger-meta.xml'):
                member = filename.split('.')[0]
                metadata_map['ApexTrigger'].add(member)
        elif folder in ('lwc', 'aura'):
            # El nombre del componente es el nombre de la carpeta parts[1]
            metadata_map[FOLDER_TO_METADATA[folder]].add(parts[1])
        elif folder == 'flexipages':
            if filename.endswith('.flexipage-meta.xml'):
                metadata_map['FlexiPage'].add(filename.replace('.flexipage-meta.xml', ''))
        elif folder == 'tabs':
            if filename.endswith('.tab-meta.xml'):
                metadata_map['CustomTab'].add(filename.replace('.tab-meta.xml', ''))
        elif folder == 'permissionsets':
            if filename.endswith('.permissionset-meta.xml'):
                metadata_map['PermissionSet'].add(filename.replace('.permissionset-meta.xml', ''))
        elif folder == 'applications':
            if filename.endswith('.app-meta.xml'):
                metadata_map['CustomApplication'].add(filename.replace('.app-meta.xml', ''))
        elif folder == 'flows':
            if filename.endswith('.flow-meta.xml'):
                metadata_map['Flow'].add(filename.replace('.flow-meta.xml', ''))
        elif folder == 'quickActions':
            if filename.endswith('.quickAction-meta.xml'):
                metadata_map['QuickAction'].add(filename.replace('.quickAction-meta.xml', ''))
        elif folder == 'approvalProcesses':
            if filename.endswith('.approvalProcess-meta.xml'):
                metadata_map['ApprovalProcess'].add(filename.replace('.approvalProcess-meta.xml', ''))
        elif folder == 'customMetadata':
            if filename.endswith('.md-meta.xml'):
                metadata_map['CustomMetadata'].add(filename.replace('.md-meta.xml', ''))
        elif folder == 'notificationtypes':
            if filename.endswith('.notiftype-meta.xml'):
                metadata_map['CustomNotificationType'].add(filename.replace('.notiftype-meta.xml', ''))
        elif folder == 'objects':
            if len(parts) >= 4 and parts[2] == 'fields':
                obj_name = parts[1]
                field_file = parts[3]
                if field_file.endswith('.field-meta.xml'):
                    field_name = field_file.replace('.field-meta.xml', '')
                    metadata_map['CustomField'].add(f'{obj_name}.{field_name}')
            elif len(parts) >= 2 and parts[1].endswith('.object-meta.xml'):
                obj_name = parts[1].replace('.object-meta.xml', '')
                metadata_map['CustomObject'].add(obj_name)
        elif folder in FOLDER_TO_METADATA:
            meta_type = FOLDER_TO_METADATA[folder]
            member = filename.split('.')[0]
            if member:
                metadata_map[meta_type].add(member)
            
    return metadata_map

def generate_package_xml(metadata_map, output_path, api_version='65.0'):
    root = ET.Element('Package', xmlns="http://soap.sforce.com/2006/04/metadata")
    
    for meta_type in sorted(metadata_map.keys()):
        members = sorted(list(metadata_map[meta_type]))
        members = [m for m in members if m and m.strip()]
        if not members:
            continue
        types_elem = ET.SubElement(root, 'types')
        for member in members:
            m_elem = ET.SubElement(types_elem, 'members')
            m_elem.text = member
        name_elem = ET.SubElement(types_elem, 'name')
        name_elem.text = meta_type
        
    version_elem = ET.SubElement(root, 'version')
    version_elem.text = api_version
    
    xml_str = ET.tostring(root, encoding='utf-8')
    dom = minidom.parseString(xml_str)
    pretty_xml = dom.toprettyxml(indent="    ", encoding="UTF-8").decode('utf-8')
    cleaned_xml = '\n'.join([line for line in pretty_xml.split('\n') if line.strip() != '']) + '\n'
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(cleaned_xml)
        
    return cleaned_xml

def main():
    parser = argparse.ArgumentParser(description="Generador determinista de package.xml acumulativo por SOL-XXXX")
    parser.add_argument('--solution', required=True, help="Identificador correlativo de la solución (ej: SOL-0369)")
    parser.add_argument('--commits', type=int, help="Número de commits recientes para extraer metadatos")
    parser.add_argument('--base', help="Rama base para el diff de Git (ej: origin/develop o origin/main)")
    parser.add_argument('--api-version', default='65.0', help="Versión de la API de Salesforce (default: 65.0)")
    parser.add_argument('--output', help="Ruta del package.xml generado")
    
    args = parser.parse_args()
    sol_id = args.solution.upper()
    if not sol_id.startswith('SOL-'):
        sol_id = 'SOL-' + sol_id
        
    output_path = args.output or f"manifest/package-{sol_id.lower()}.xml"
    
    changed_files = get_changed_files(sol_id, args.commits, args.base)
    metadata_map = extract_metadata_members(changed_files)
    
    total_components = sum(len(v) for v in metadata_map.values())
    if total_components == 0:
        print(f"[!] No se detectaron archivos vinculados a {sol_id}. Reintentando con últimos 5 commits...")
        changed_files = get_changed_files(sol_id, commits_count=5)
        metadata_map = extract_metadata_members(changed_files)
        total_components = sum(len(v) for v in metadata_map.values())
        
    print(f"\n============================================================")
    print(f"📦 MANIFIESTO ACUMULATIVO DETERMINISTA: {sol_id}")
    print(f"============================================================")
    print(f"[*] Archivos auditados: {len(changed_files)}")
    print(f"[*] Tipos de metadatos: {len(metadata_map)}")
    print(f"[*] Componentes totales: {total_components}\n")
    
    for meta_type, members in sorted(metadata_map.items()):
        print(f"  • {meta_type} ({len(members)}):")
        for m in sorted(list(members)):
            print(f"      - {m}")
            
    xml_content = generate_package_xml(metadata_map, output_path, args.api_version)
    print(f"\n[+] Archivo generado: {output_path}")
    print("=" * 60)
    print(xml_content.strip())
    print("=" * 60 + "\n")

if __name__ == '__main__':
    main()
