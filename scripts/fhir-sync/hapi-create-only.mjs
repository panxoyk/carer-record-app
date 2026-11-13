const PINNED_HAPI = { name: 'HAPI FHIR Server', version: '8.12.0' };

export function assertHapiVersionZeroCreateSupport(capability, resourceTypes) {
  if (
    capability?.resourceType !== 'CapabilityStatement' ||
    !/^4\.0\./.test(capability.fhirVersion ?? '') ||
    capability.software?.name !== PINNED_HAPI.name ||
    capability.software?.version !== PINNED_HAPI.version
  ) throw new Error('Create-only PUT requires the pinned HAPI FHIR 8.12.0 R4 server');
  const rest = (capability.rest ?? []).filter((entry) => entry.mode === 'server');
  for (const type of new Set(resourceTypes)) {
    if (!rest.some((entry) => entry.resource?.some((resource) => resource.type === type && resource.versioning === 'versioned-update'))) {
      throw new Error(`Create-only PUT requires HAPI versioned-update support for ${type}`);
    }
  }
}

export const HAPI_VERSION_ZERO_MATCH = 'W/"0"';
