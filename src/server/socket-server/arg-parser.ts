type MapPrimitive<T> =
  T extends 'number' ? number :
  T extends 'string' ? string :
  never;

/** Strings used to represent primitive types that can be used as an argument */
export type TypePrimitiveIndicator = 'number' | 'string';

/** Primitive types that can be used as an argument */
export type PrimitiveTypes = number | string;

/**
 * Indicates the valid arguments for a callback, which is either a tuple of elements indicating the valid types,
 * or a single type indicating it is an array of that type
 */
export type ArgumentsIndicator = TypePrimitiveIndicator | readonly TypePrimitiveIndicator[];

/** Map a type indicator to its actual argument type */
export type GetArgumentsType<T extends ArgumentsIndicator> = T extends readonly TypePrimitiveIndicator[] ? {
  [K in keyof T]: MapPrimitive<T[K]>;
} : T extends 'number' ? number[] : string[];

const parseFiniteNumber = (value: string): number | null => {
  // Number('') and Number('   ') both evaluate to zero, which is unsafe for a
  // network protocol: a missing numeric field must never be silently converted
  // into a valid gameplay value. Infinity is rejected for the same reason.
  if (value.trim().length === 0) {
    return null;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};

export const parseArgs = <Arguments extends ArgumentsIndicator>(args: Array<string>, types: Arguments): GetArgumentsType<Arguments> | null => {
  if (types === 'string') {
    return args as GetArgumentsType<Arguments>;
  }

  if (types === 'number') {
    const numbers: number[] = [];
    for (const arg of args) {
      const parsed = parseFiniteNumber(arg);
      if (parsed === null) {
        return null;
      }
      numbers.push(parsed);
    }
    return numbers as GetArgumentsType<Arguments>;
  }

  if (args.length !== types.length) {
    return null;
  }

  const converted: PrimitiveTypes[] = [];
  for (let i = 0; i < args.length; i += 1) {
    if (types[i] === 'string') {
      converted.push(args[i]);
      continue;
    }

    const parsed = parseFiniteNumber(args[i]);
    if (parsed === null) {
      return null;
    }
    converted.push(parsed);
  }

  return converted as GetArgumentsType<Arguments>;
};